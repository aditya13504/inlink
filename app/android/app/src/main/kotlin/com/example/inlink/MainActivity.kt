package com.example.inlink

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.ArrayDeque

/**
 * Experimental BLE transport for opaque InLink protocol frames.
 *
 * BLE provides no end-to-end authenticity or delivery guarantee. The Flutter
 * layer must authenticate/decrypt complete envelopes and validate receipts.
 */
class MainActivity : FlutterActivity() {
    private val methodChannelName = "inlink/network"
    private val eventChannelName = "inlink/network-events"
    private val permissionRequestCode = 4817

    private val serviceUuid: UUID = UUID.fromString("9f3a1000-7b4d-4f3c-9a12-2f6e1a000001")
    private val frameCharacteristicUuid: UUID =
        UUID.fromString("9f3a1001-7b4d-4f3c-9a12-2f6e1a000001")
    private val cccdUuid: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private var eventSink: EventChannel.EventSink? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var scanner: BluetoothLeScanner? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private val clientGatts = mutableMapOf<String, BluetoothGatt>()
    private val connectingAddresses = mutableSetOf<String>()
    private val maxClientPeers = 3
    private var frameCharacteristic: BluetoothGattCharacteristic? = null
    private var isScanning = false
    private var isAdvertising = false
    private data class PendingFrame(val bytes: ByteArray, val result: MethodChannel.Result, val targetPeer: String? = null)
    private val outgoingFrames = ArrayDeque<PendingFrame>()
    private var activeFrame: PendingFrame? = null
    private val maxQueuedFrames = 128

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = manager.adapter

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCapabilities" -> result.success(capabilities())
                    "startBle" -> {
                        if (!hasBlePermissions()) {
                            // A platform permission prompt can only complete one
                            // MethodChannel result. Do not overwrite an earlier
                            // pending call and leave its Dart Future unresolved.
                            if (pendingStartResult != null) {
                                result.error(
                                    "ble_permission_request_in_progress",
                                    "A Bluetooth permission request is already in progress.",
                                    null
                                )
                            } else {
                                pendingStartResult = result
                                try {
                                    requestBlePermissions()
                                } catch (e: Exception) {
                                    pendingStartResult = null
                                    result.error(
                                        "ble_permission_request_failed",
                                        e.message ?: "Unable to request Bluetooth permissions.",
                                        null
                                    )
                                }
                            }
                        } else {
                            startBle(result)
                        }
                    }
                    "stopBle" -> {
                        stopBle()
                        result.success(mapOf("stopped" to true))
                    }
                    "getConnectedPeers" -> result.success(connectedPeerAddresses())
                    "sendBleFrame" -> {
                        val raw = call.argument<ByteArray>("frame")
                        if (raw == null || raw.isEmpty() || raw.size > 194) {
                            result.error("invalid_frame", "Frame must contain 1-194 bytes.", null)
                        } else {
                            sendFrame(raw, result, call.argument<String>("peer"))
                        }
                    }
                    "sendBleFrameToPeer" -> {
                        val raw = call.argument<ByteArray>("frame")
                        val peer = call.argument<String>("peer")
                        if (raw == null || raw.isEmpty() || raw.size > 194 || peer.isNullOrBlank()) {
                            result.error("invalid_frame", "Frame must contain 1-194 bytes and a target peer.", null)
                        } else {
                            sendFrame(raw, result, peer)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun capabilities(): Map<String, Any> = mapOf(
        "platformName" to "Android",
        "bleSupported" to (bluetoothAdapter != null),
        "bleImplemented" to true,
        "internetRelayImplemented" to false,
        "multiPeerBleImplemented" to true,
        "maxOutboundPeers" to maxClientPeers,
        "note" to "Experimental multi-peer GATT sessions with bounded outbound peers. Peer addresses are transport handles, not authenticated InLink identities. Physical-device testing required."
    )

    private fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun hasBlePermissions(): Boolean =
        requiredPermissions().all {
            ActivityCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

    private fun requestBlePermissions() {
        ActivityCompat.requestPermissions(this, requiredPermissions(), permissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            val result = pendingStartResult
            pendingStartResult = null
            if (grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED } &&
                hasBlePermissions()
            ) {
                if (result != null) startBle(result)
            } else {
                result?.error("ble_permission_denied", "Bluetooth permissions were denied or not fully granted.", null)
                emit("permissionDenied", mapOf("permissions" to permissions.toList()))
            }
        }
    }

    private fun startBle(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.error("ble_unavailable", "This device has no Bluetooth adapter.", null)
            return
        }
        try {
            if (!adapter.isEnabled) {
                result.error("bluetooth_disabled", "Enable Bluetooth and try again.", null)
                return
            }
            scanner = adapter.bluetoothLeScanner
            advertiser = adapter.bluetoothLeAdvertiser
            if (scanner == null || advertiser == null) {
                result.error("ble_role_unavailable", "BLE scanning or advertising is unavailable on this device.", null)
                return
            }
            openGattServer()
            startAdvertising()
            startScanning()
            result.success(mapOf("started" to true, "serviceUuid" to serviceUuid.toString()))
            emit("started", mapOf("serviceUuid" to serviceUuid.toString()))
        } catch (e: SecurityException) {
            stopBle()
            result.error("ble_permission", e.message ?: "Missing Bluetooth permission.", null)
        } catch (e: Exception) {
            stopBle()
            result.error("ble_start_failed", e.message ?: "Unable to start BLE.", null)
        }
    }

    private fun openGattServer() {
        val service = BluetoothGattService(serviceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        frameCharacteristic = BluetoothGattCharacteristic(
            frameCharacteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY or
                BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_WRITE or BluetoothGattCharacteristic.PERMISSION_READ
        ).apply {
            addDescriptor(
                BluetoothGattDescriptor(
                    cccdUuid,
                    BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
                )
            )
        }
        service.addCharacteristic(frameCharacteristic)
        gattServer = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
            .openGattServer(this, serverCallback)
        if (gattServer?.addService(service) != true) {
            emit("error", mapOf("message" to "Could not register BLE GATT service."))
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                emit("peerConnected", mapOf("peer" to device.address, "role" to "server"))
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                if (activeFrame?.targetPeer == device.address) {
                    completeActiveFrameError("peer_disconnected", "Target BLE peer disconnected during frame transfer.")
                }
                emit("peerDisconnected", mapOf("peer" to device.address, "role" to "server", "status" to status))
            }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            val active = activeFrame ?: return
            if (active.targetPeer != null && active.targetPeer != device.address) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                completeActiveFrameSuccess(mapOf("accepted" to true, "path" to "gatt-notify", "peer" to device.address))
            } else {
                completeActiveFrameError("notify_failed", "GATT notification failed with status $status.")
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (characteristic.uuid != frameCharacteristicUuid || offset != 0 || value.isEmpty() || value.size > 194) {
                if (responseNeeded) gattServer?.sendResponse(
                    device, requestId, BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH, offset, null
                )
                return
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
            emit("frameReceived", mapOf("peer" to device.address, "frame" to value.toList()))
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (descriptor.uuid == cccdUuid && offset == 0 &&
                (value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) ||
                 value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE))) {
                descriptor.value = value
                if (responseNeeded) gattServer?.sendResponse(
                    device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null
                )
                if (value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) {
                    emit("readyToSend", mapOf("peer" to device.address, "role" to "server"))
                    pumpFrameQueue()
                }
            } else if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, offset, null)
            }
        }
    }

    private fun startAdvertising() {
        val adv = advertiser ?: return
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(serviceUuid))
            .build()
        adv.startAdvertising(settings, data, advertiseCallback)
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            isAdvertising = true
            emit("advertising", mapOf("active" to true))
        }

        override fun onStartFailure(errorCode: Int) {
            isAdvertising = false
            emit("error", mapOf("operation" to "advertising", "code" to errorCode))
        }
    }

    private fun startScanning() {
        if (isScanning || clientGatts.size + connectingAddresses.size >= maxClientPeers) return
        val bleScanner = scanner ?: return
        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(serviceUuid)).build())
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        bleScanner.startScan(filters, settings, scanCallback)
        isScanning = true
        emit("scanning", mapOf("active" to true))
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            if (clientGatts.containsKey(device.address) || connectingAddresses.contains(device.address) ||
                clientGatts.size + connectingAddresses.size >= maxClientPeers) return
            try {
                emit("peerFound", mapOf("peer" to device.address, "rssi" to result.rssi))
                connectingAddresses.add(device.address)
                if (clientGatts.size + connectingAddresses.size >= maxClientPeers) stopScanningOnly()
                device.connectGatt(this@MainActivity, false, clientCallback, BluetoothDevice.TRANSPORT_LE)
            } catch (e: SecurityException) {
                connectingAddresses.remove(device.address)
                emit("error", mapOf("operation" to "connect", "message" to (e.message ?: "Permission denied")))
                if (hasBlePermissions()) startScanning()
            } catch (e: Exception) {
                connectingAddresses.remove(device.address)
                emit("error", mapOf("operation" to "connect", "message" to (e.message ?: "BLE connection failed")))
                if (hasBlePermissions()) startScanning()
            }
        }

        override fun onScanFailed(errorCode: Int) {
            isScanning = false
            emit("error", mapOf("operation" to "scan", "code" to errorCode))
        }
    }

    private val clientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                connectingAddresses.remove(gatt.device.address)
                if (clientGatts.size >= maxClientPeers) {
                    try { gatt.disconnect() } catch (_: Exception) { }
                    try { gatt.close() } catch (_: Exception) { }
                    return
                }
                clientGatts[gatt.device.address] = gatt
                emit("peerConnected", mapOf("peer" to gatt.device.address, "role" to "client"))
                // The v1 frame can be up to 194 bytes, larger than the default
                // ATT payload. Request a larger MTU before enabling frame writes.
                if (!gatt.requestMtu(247)) gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                val wasCurrentConnection = clientGatts[gatt.device.address] === gatt
                connectingAddresses.remove(gatt.device.address)
                if (wasCurrentConnection) {
                    clientGatts.remove(gatt.device.address)
                    if (activeFrame?.targetPeer == gatt.device.address) {
                        completeActiveFrameError("peer_disconnected", "Target BLE peer disconnected during frame transfer.")
                    }
                }
                emit("peerDisconnected", mapOf("peer" to gatt.device.address, "role" to "client", "status" to status))
                try { gatt.close() } catch (_: Exception) { }
                // A failed connection may already have been cleaned up by a
                // service/notification failure handler. Only the current
                // connection is allowed to schedule a reconnect scan.
                if (hasBlePermissions()) startScanning()
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            emit("mtuChanged", mapOf("peer" to gatt.device.address, "mtu" to mtu, "status" to status))
            gatt.discoverServices()
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val characteristic = gatt.getService(serviceUuid)?.getCharacteristic(frameCharacteristicUuid)
            if (status != BluetoothGatt.GATT_SUCCESS || characteristic == null) {
                emit("error", mapOf("operation" to "discoverServices", "status" to status,
                    "message" to "InLink GATT service not found."))
                recoverClientConnection(gatt, "service_discovery_failed",
                    "InLink GATT service was unavailable or service discovery failed.")
                return
            }
            val enabled = gatt.setCharacteristicNotification(characteristic, true)
            val descriptor = characteristic.getDescriptor(cccdUuid)
            if (enabled && descriptor != null) {
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                if (!gatt.writeDescriptor(descriptor)) {
                    emit("error", mapOf("operation" to "subscribeNotifications", "message" to "Android rejected the CCCD write."))
                    recoverClientConnection(gatt, "subscription_failed",
                        "Android rejected the notification subscription request.")
                }
            } else {
                emit("error", mapOf("operation" to "subscribeNotifications", "message" to "Notification characteristic setup failed."))
                recoverClientConnection(gatt, "subscription_failed",
                    "Notification characteristic or CCCD was unavailable.")
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int
        ) {
            if (descriptor.uuid != cccdUuid) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                emit("readyToSend", mapOf("peer" to gatt.device.address, "role" to "client"))
                pumpFrameQueue()
                if (clientGatts.size + connectingAddresses.size < maxClientPeers) startScanning()
            } else {
                emit("error", mapOf("operation" to "subscribeNotifications", "status" to status))
                recoverClientConnection(gatt, "subscription_failed",
                    "The remote device rejected notification subscription.")
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            if (characteristic.uuid == frameCharacteristicUuid) {
                emit("frameReceived", mapOf("peer" to gatt.device.address, "frame" to value.toList()))
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33 && characteristic.uuid == frameCharacteristicUuid) {
                emit("frameReceived", mapOf("peer" to gatt.device.address, "frame" to characteristic.value.toList()))
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (clientGatts[gatt.device.address] !== gatt) return
            if (activeFrame?.targetPeer != null && activeFrame?.targetPeer != gatt.device.address) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                emit("frameSent", mapOf("peer" to gatt.device.address, "operation" to "write", "status" to status))
                completeActiveFrameSuccess(mapOf("accepted" to true, "path" to "gatt-write", "peer" to gatt.device.address))
            } else {
                emit("error", mapOf("peer" to gatt.device.address, "operation" to "write", "status" to status))
                completeActiveFrameError("write_failed", "GATT write failed with status $status.")
            }
        }
    }

    /**
     * Tear down an unusable client GATT session and resume discovery.
     *
     * Cleans up one failed outbound GATT session. This is not a promise of
     * continuous background mesh or authenticated peer identity.
     */
    private fun recoverClientConnection(gatt: BluetoothGatt, code: String, message: String) {
        if (clientGatts[gatt.device.address] !== gatt) return
        clientGatts.remove(gatt.device.address)
        connectingAddresses.remove(gatt.device.address)
        if (activeFrame?.targetPeer == gatt.device.address) completeActiveFrameError(code, message)
        try { gatt.disconnect() } catch (_: Exception) { }
        try { gatt.close() } catch (_: Exception) { }
        emit("recovery", mapOf("operation" to "clientGatt", "peer" to gatt.device.address, "action" to "resumeScan", "reason" to code))
        try {
            if (hasBlePermissions()) startScanning()
        } catch (e: SecurityException) {
            emit("error", mapOf("operation" to "recoveryScan", "message" to (e.message ?: "Bluetooth permission denied")))
        } catch (e: Exception) {
            emit("error", mapOf("operation" to "recoveryScan", "message" to (e.message ?: "Unable to resume BLE scan")))
        }
    }

    @Suppress("DEPRECATION")
    private fun sendFrame(frame: ByteArray, result: MethodChannel.Result, targetPeer: String? = null) {
        if (!hasBlePermissions()) {
            result.error("ble_permission", "Call startBle and grant permissions first.", null)
            return
        }
        if (frame.isEmpty() || frame.size > 194) {
            result.error("invalid_frame", "Frame must contain 1-194 bytes.", null)
            return
        }
        if (outgoingFrames.size >= maxQueuedFrames) {
            result.error("send_queue_full", "BLE send queue is full; retry after it drains.", null)
            return
        }
        if (targetPeer != null && connectedPeerAddresses().none { it.equals(targetPeer, ignoreCase = true) }) {
            result.error("peer_not_connected", "The requested BLE peer is not connected and ready.", null)
            return
        }
        outgoingFrames.addLast(PendingFrame(frame.copyOf(), result, targetPeer?.uppercase()))
        pumpFrameQueue()
    }

    @Suppress("DEPRECATION")
    private fun pumpFrameQueue() {
        if (activeFrame != null || outgoingFrames.isEmpty()) return
        if (!hasBlePermissions()) {
            failFrameQueue("ble_permission", "Bluetooth permission is no longer available.")
            return
        }
        val next = outgoingFrames.removeFirst()
        activeFrame = next
        try {
            val preferred = next.targetPeer
            val gatt = if (preferred != null) clientGatts[preferred] else clientGatts.values.firstOrNull()
            val characteristic = gatt?.getService(serviceUuid)?.getCharacteristic(frameCharacteristicUuid)
            if (gatt != null && characteristic != null) {
                characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                characteristic.value = next.bytes
                val accepted = gatt.writeCharacteristic(characteristic)
                if (!accepted) completeActiveFrameError("write_rejected", "Android rejected the GATT write request.")
                return
            }

            val server = gattServer
            val localCharacteristic = frameCharacteristic
            val connected = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
                .getConnectedDevices(BluetoothProfile.GATT)
            val device = if (preferred != null) connected.firstOrNull { it.address == preferred } else connected.firstOrNull()
            if (server != null && localCharacteristic != null && device != null) {
                localCharacteristic.value = next.bytes
                if (!server.notifyCharacteristicChanged(device, localCharacteristic, false)) {
                    completeActiveFrameError("notify_rejected", "Android rejected the GATT notification.")
                }
                // Completion comes from onNotificationSent; do not overlap notifications.
                return
            }
            completeActiveFrameError("no_peer", "No matching connected BLE peer is ready. Start BLE on nearby phones and wait for readiness.")
        } catch (e: SecurityException) {
            completeActiveFrameError("ble_permission", e.message ?: "Missing Bluetooth permission.")
        } catch (e: Exception) {
            completeActiveFrameError("send_failed", e.message ?: "BLE send failed.")
        }
    }

    private fun completeActiveFrameSuccess(details: Map<String, Any?>) {
        val completed = activeFrame ?: return
        activeFrame = null
        completed.result.success(details)
        pumpFrameQueue()
    }

    private fun completeActiveFrameError(code: String, message: String) {
        val failed = activeFrame ?: return
        activeFrame = null
        failed.result.error(code, message, null)
        pumpFrameQueue()
    }

    private fun failFrameQueue(code: String, message: String) {
        val active = activeFrame
        activeFrame = null
        active?.result?.error(code, message, null)
        while (outgoingFrames.isNotEmpty()) {
            outgoingFrames.removeFirst().result.error(code, message, null)
        }
    }

    private fun stopScanningOnly() {
        try {
            if (isScanning && hasBlePermissions()) scanner?.stopScan(scanCallback)
        } catch (_: Exception) { }
        isScanning = false
    }

    private fun stopBle() {
        failFrameQueue("ble_stopped", "BLE was stopped before the queued frame was sent.")
        stopScanningOnly()
        try {
            if (isAdvertising && hasBlePermissions()) advertiser?.stopAdvertising(advertiseCallback)
        } catch (_: Exception) { }
        isAdvertising = false
        clientGatts.values.toList().forEach { gatt ->
            try { gatt.disconnect() } catch (_: Exception) { }
            try { gatt.close() } catch (_: Exception) { }
        }
        clientGatts.clear()
        connectingAddresses.clear()
        try { gattServer?.close() } catch (_: Exception) { }
        gattServer = null
        frameCharacteristic = null
        emit("stopped", mapOf("stopped" to true))
    }

    private fun connectedPeerAddresses(): List<String> {
        val peers = linkedSetOf<String>()
        peers.addAll(clientGatts.keys)
        try {
            if (hasBlePermissions()) {
                val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                peers.addAll(manager.getConnectedDevices(BluetoothProfile.GATT).map { it.address })
            }
        } catch (_: Exception) { }
        return peers.toList().sorted()
    }

    private fun emit(type: String, fields: Map<String, Any?> = emptyMap()) {
        val event = mutableMapOf<String, Any?>("type" to type)
        event.putAll(fields)
        runOnUiThread { eventSink?.success(event) }
    }

    override fun onDestroy() {
        // Avoid leaving a Dart-side startBle Future pending if the activity is
        // destroyed while Android's runtime permission dialog is open.
        pendingStartResult?.error(
            "activity_destroyed",
            "The activity was destroyed before Bluetooth permissions completed.",
            null
        )
        pendingStartResult = null
        stopBle()
        super.onDestroy()
    }
}
