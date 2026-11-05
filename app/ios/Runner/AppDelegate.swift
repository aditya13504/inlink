import Flutter
import UIKit
import CoreBluetooth

@main
@objc class AppDelegate: FlutterAppDelegate, CBCentralManagerDelegate,
                         CBPeripheralManagerDelegate, CBPeripheralDelegate {
  private let networkChannelName = "inlink/network"
  private let eventChannelName = "inlink/network-events"
  private let serviceUUID = CBUUID(string: "9F3A1000-7B4D-4F3C-9A12-2F6E1A000001")
  private let frameCharacteristicUUID = CBUUID(string: "9F3A1001-7B4D-4F3C-9A12-2F6E1A000001")
  private let maxPeers = 3
  private let maxFrameBytes = 194

  private var methodChannel: FlutterMethodChannel?
  private var eventSink: FlutterEventSink?
  private var central: CBCentralManager!
  private var peripheralManager: CBPeripheralManager!
  private var localCharacteristic: CBMutableCharacteristic?
  private var discovered: [UUID: CBPeripheral] = [:]
  private var connecting = Set<UUID>()
  private var connected: [UUID: CBPeripheral] = [:]
  private var remoteCharacteristics: [UUID: CBCharacteristic] = [:]
  private var subscribedCentrals: [UUID: CBCentral] = [:]
  private var scanning = false
  private var isAdvertising = false
  private var isStarted = false
  private var pendingStartResult: FlutterResult?
  private var activeSend: PendingSend?
  private var activePeerHandle: String?
  private var sendQueue: [PendingSend] = []
  private let maxQueuedFrames = 128

  private struct PendingSend {
    let frame: Data
    let peer: String?
    let result: FlutterResult
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let methods = FlutterMethodChannel(name: networkChannelName, binaryMessenger: controller.binaryMessenger)
      methodChannel = methods
      methods.setMethodCallHandler { [weak self] call, result in
        self?.handleMethod(call, result: result)
      }
      FlutterEventChannel(name: eventChannelName, binaryMessenger: controller.binaryMessenger)
        .setStreamHandler(self)
    }
    central = CBCentralManager(delegate: self, queue: nil)
    peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMethod(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCapabilities":
      result([
        "platformName": "iOS",
        "bleSupported": true,
        "bleImplemented": true,
        "internetRelayImplemented": false,
        "multiPeerBleImplemented": true,
        "maxOutboundPeers": maxPeers,
        "note": "Experimental CoreBluetooth central/peripheral transport; physical-device interoperability and background behavior require validation."
      ])
    case "startBle":
      if isStarted {
        result(["started": true, "serviceUuid": serviceUUID.uuidString])
      } else if central.state == .poweredOn && peripheralManager.state == .poweredOn {
        startTransport(result: result)
      } else if pendingStartResult != nil {
        result(FlutterError(code: "ble_start_in_progress", message: "Bluetooth startup is already in progress.", details: nil))
      } else {
        pendingStartResult = result
        if central.state == .unauthorized || peripheralManager.state == .unauthorized {
          pendingStartResult = nil
          result(FlutterError(code: "ble_permission", message: "Bluetooth permission is denied. Enable Bluetooth access in Settings.", details: nil))
        } else if central.state == .poweredOff || peripheralManager.state == .poweredOff {
          pendingStartResult = nil
          result(FlutterError(code: "bluetooth_disabled", message: "Enable Bluetooth and try again.", details: nil))
        } else {
          emit("starting", fields: [:])
        }
      }
    case "stopBle":
      stopTransport()
      result(["stopped": true])
    case "getConnectedPeers":
      result(connectedPeerHandles())
    case "sendBleFrame", "sendBleFrameToPeer":
      guard let args = call.arguments as? [String: Any],
            let frame = args["frame"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_frame", message: "A byte frame is required.", details: nil))
        return
      }
      let peer = args["peer"] as? String
      if call.method == "sendBleFrameToPeer" && (peer?.isEmpty ?? true) {
        result(FlutterError(code: "invalid_frame", message: "A target peer is required.", details: nil))
        return
      }
      sendFrame(frame.data, peer: peer, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startTransport(result: @escaping FlutterResult) {
    guard central.state == .poweredOn, peripheralManager.state == .poweredOn else {
      result(FlutterError(code: "ble_unavailable", message: "Bluetooth is not powered on.", details: nil))
      return
    }
    isStarted = true
    startAdvertising()
    startScanning()
    result(["started": true, "serviceUuid": serviceUUID.uuidString])
    emit("started", fields: ["serviceUuid": serviceUUID.uuidString])
  }

  private func startAdvertising() {
    guard peripheralManager.state == .poweredOn, !isAdvertising else { return }
    let characteristic = CBMutableCharacteristic(
      type: frameCharacteristicUUID,
      properties: [.write, .writeWithoutResponse, .notify, .read],
      value: nil,
      permissions: [.readable, .writeable]
    )
    let service = CBMutableService(type: serviceUUID, primary: true)
    service.characteristics = [characteristic]
    localCharacteristic = characteristic
    peripheralManager.removeAllServices()
    peripheralManager.add(service)
  }

  private func startScanning() {
    guard isStarted, central.state == .poweredOn, !scanning,
          connected.count < maxPeers else { return }
    central.scanForPeripherals(withServices: [serviceUUID],
                               options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    scanning = true
    emit("scanning", fields: ["active": true])
  }

  private func stopScanning() {
    if scanning { central.stopScan() }
    scanning = false
  }

  private func stopTransport() {
    isStarted = false
    stopScanning()
    peripheralManager.stopAdvertising()
    peripheralManager.removeAllServices()
    isAdvertising = false
    for peer in connected.values { central.cancelPeripheralConnection(peer) }
    for handle in connected.keys { emit("peerDisconnected", fields: ["peer": handle.uuidString, "role": "client"]) }
    for handle in subscribedCentrals.keys { emit("peerDisconnected", fields: ["peer": handle.uuidString, "role": "server"]) }
    connected.removeAll()
    connecting.removeAll()
    discovered.removeAll()
    remoteCharacteristics.removeAll()
    subscribedCentrals.removeAll()
    if let active = activeSend {
      active.result(FlutterError(code: "ble_stopped", message: "BLE stopped during send.", details: nil))
      activeSend = nil
      activePeerHandle = nil
    }
    for pending in sendQueue {
      pending.result(FlutterError(code: "ble_stopped", message: "BLE stopped before send.", details: nil))
    }
    sendQueue.removeAll()
    emit("stopped", fields: ["stopped": true])
  }

  private func connectedPeerHandles() -> [String] {
    let handles = Set(connected.keys.map { $0.uuidString })
      .union(subscribedCentrals.keys.map { $0.uuidString })
    return handles.sorted()
  }

  private func sendFrame(_ frame: Data, peer: String?, result: @escaping FlutterResult) {
    guard isStarted else {
      result(FlutterError(code: "ble_not_started", message: "Start BLE before sending.", details: nil))
      return
    }
    guard !frame.isEmpty && frame.count <= maxFrameBytes else {
      result(FlutterError(code: "invalid_frame", message: "Frame must contain 1-194 bytes.", details: nil))
      return
    }
    if let peer = peer, !connected.keys.contains(where: { $0.uuidString.caseInsensitiveCompare(peer) == .orderedSame }) {
      result(FlutterError(code: "peer_not_connected", message: "The target BLE peer is not connected and ready.", details: nil))
      return
    }
    guard sendQueue.count < maxQueuedFrames else {
      result(FlutterError(code: "send_queue_full", message: "BLE send queue is full.", details: nil))
      return
    }
    sendQueue.append(PendingSend(frame: frame, peer: peer, result: result))
    pumpSendQueue()
  }

  private func pumpSendQueue() {
    guard activeSend == nil, !sendQueue.isEmpty else { return }
    let pending = sendQueue.removeFirst()
    activeSend = pending
    let target: CBPeripheral?
    if let handle = pending.peer,
       let uuid = UUID(uuidString: handle) {
      target = connected[uuid]
    } else {
      target = connected.values.first
    }
    if let target = target, let characteristic = remoteCharacteristics[target.identifier] {
      activePeerHandle = target.identifier.uuidString
      let maximum = target.maximumWriteValueLength(for: .withResponse)
      guard pending.frame.count <= maximum else {
        completeActive(error: FlutterError(
          code: "frame_exceeds_mtu",
          message: "Frame exceeds the negotiated iOS BLE write limit (\(maximum) bytes).",
          details: nil
        ))
        return
      }
      target.writeValue(pending.frame, for: characteristic, type: .withResponse)
      return
    }
    if let handle = pending.peer,
       let uuid = UUID(uuidString: handle),
       let subscribed = subscribedCentrals[uuid],
       let characteristic = localCharacteristic {
      activePeerHandle = handle
      guard peripheralManager.updateValue(pending.frame, for: characteristic, onSubscribedCentrals: [subscribed]) else {
        completeActive(error: FlutterError(code: "notify_backpressure", message: "BLE notification buffer is full; retry later.", details: nil))
        return
      }
      completeActive(success: ["accepted": true, "path": "gatt-notify", "peer": handle])
      return
    }
    if let characteristic = localCharacteristic,
       let subscribed = subscribedCentrals.values.first {
      let handle = subscribed.identifier.uuidString
      activePeerHandle = handle
      guard peripheralManager.updateValue(pending.frame, for: characteristic, onSubscribedCentrals: [subscribed]) else {
        completeActive(error: FlutterError(code: "notify_backpressure", message: "BLE notification buffer is full; retry later.", details: nil))
        return
      }
      completeActive(success: ["accepted": true, "path": "gatt-notify", "peer": handle])
      return
    }
    completeActive(error: FlutterError(code: "no_peer", message: "No matching connected BLE peer is ready.", details: nil))
  }

  private func completeActive(success: [String: Any]) {
    guard let pending = activeSend else { return }
    activeSend = nil
    activePeerHandle = nil
    pending.result(success)
    pumpSendQueue()
  }

  private func completeActive(error: FlutterError) {
    guard let pending = activeSend else { return }
    activeSend = nil
    activePeerHandle = nil
    pending.result(error)
    pumpSendQueue()
  }

  private func emit(_ type: String, fields: [String: Any]) {
    var event: [String: Any] = ["type": type]
    fields.forEach { event[$0.key] = $0.value }
    DispatchQueue.main.async { self.eventSink?(event) }
  }

  // MARK: CBCentralManagerDelegate

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn {
      completePendingStartIfReady()
      if isStarted { startScanning() }
    } else {
      if isStarted { stopTransport() }
      stopScanning()
      emit("error", fields: ["operation": "centralState", "state": central.state.rawValue])
      failPendingStartIfUnavailable()
    }
  }

  private func completePendingStartIfReady() {
    guard let result = pendingStartResult,
          central.state == .poweredOn, peripheralManager.state == .poweredOn else { return }
    pendingStartResult = nil
    startTransport(result: result)
  }

  private func failPendingStartIfUnavailable() {
    guard let result = pendingStartResult else { return }
    if central.state == .unauthorized || peripheralManager.state == .unauthorized {
      pendingStartResult = nil
      result(FlutterError(code: "ble_permission", message: "Bluetooth permission denied.", details: nil))
    } else if central.state == .poweredOff || peripheralManager.state == .poweredOff {
      pendingStartResult = nil
      result(FlutterError(code: "bluetooth_disabled", message: "Enable Bluetooth and try again.", details: nil))
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                      advertisementData: [String: Any], rssi RSSI: NSNumber) {
    guard isStarted, connected[peripheral.identifier] == nil,
          !connecting.contains(peripheral.identifier),
          connected.count + connecting.count < maxPeers else { return }
    discovered[peripheral.identifier] = peripheral
    connecting.insert(peripheral.identifier)
    emit("peerFound", fields: ["peer": peripheral.identifier.uuidString, "rssi": RSSI.intValue])
    stopScanning()
    peripheral.delegate = self
    central.connect(peripheral, options: nil)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    connecting.remove(peripheral.identifier)
    guard connected.count < maxPeers else {
      central.cancelPeripheralConnection(peripheral)
      startScanning()
      return
    }
    connected[peripheral.identifier] = peripheral
    emit("peerConnected", fields: ["peer": peripheral.identifier.uuidString, "role": "client"])
    peripheral.discoverServices([serviceUUID])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    connecting.remove(peripheral.identifier)
    connected.removeValue(forKey: peripheral.identifier)
    remoteCharacteristics.removeValue(forKey: peripheral.identifier)
    emit("error", fields: ["operation": "connect", "message": error?.localizedDescription ?? "BLE connection failed"])
    startScanning()
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    connecting.remove(peripheral.identifier)
    connected.removeValue(forKey: peripheral.identifier)
    remoteCharacteristics.removeValue(forKey: peripheral.identifier)
    if activePeerHandle == peripheral.identifier.uuidString { completeActive(error: FlutterError(code: "peer_disconnected", message: "Peer disconnected during send.", details: nil)) }
    emit("peerDisconnected", fields: ["peer": peripheral.identifier.uuidString, "role": "client"])
    startScanning()
  }

  // MARK: CBPeripheralDelegate

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
      emit("error", fields: ["operation": "discoverServices", "peer": peripheral.identifier.uuidString])
      central.cancelPeripheralConnection(peripheral)
      return
    }
    peripheral.discoverCharacteristics([frameCharacteristicUUID], for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard error == nil, let characteristic = service.characteristics?.first(where: { $0.uuid == frameCharacteristicUUID }) else {
      emit("error", fields: ["operation": "discoverCharacteristics", "peer": peripheral.identifier.uuidString])
      central.cancelPeripheralConnection(peripheral)
      return
    }
    remoteCharacteristics[peripheral.identifier] = characteristic
    if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
      peripheral.setNotifyValue(true, for: characteristic)
    } else {
      emit("error", fields: ["operation": "subscribeNotifications", "peer": peripheral.identifier.uuidString])
      central.cancelPeripheralConnection(peripheral)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let error = error {
      emit("error", fields: ["operation": "subscribeNotifications", "message": error.localizedDescription])
      central.cancelPeripheralConnection(peripheral)
      return
    }
    if characteristic.isNotifying {
      emit("readyToSend", fields: ["peer": peripheral.identifier.uuidString, "role": "client"])
      startScanning()
      pumpSendQueue()
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard error == nil, characteristic.uuid == frameCharacteristicUUID,
          let value = characteristic.value, !value.isEmpty, value.count <= maxFrameBytes else { return }
    emit("frameReceived", fields: ["peer": peripheral.identifier.uuidString, "frame": [UInt8](value)])
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == frameCharacteristicUUID else { return }
    if let error = error {
      completeActive(error: FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
    } else {
      completeActive(success: ["accepted": true, "path": "gatt-write", "peer": peripheral.identifier.uuidString])
    }
  }

  // MARK: CBPeripheralManagerDelegate

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state == .poweredOn {
      completePendingStartIfReady()
      if isStarted { startAdvertising() }
    } else {
      if isStarted { stopTransport() }
      isAdvertising = false
      emit("error", fields: ["operation": "peripheralState", "state": peripheral.state.rawValue])
      failPendingStartIfUnavailable()
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    if let error = error {
      emit("error", fields: ["operation": "addService", "message": error.localizedDescription])
      return
    }
    guard isStarted else { return }
    peripheralManager.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
    ])
  }

  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    isAdvertising = error == nil
    if let error = error {
      emit("error", fields: ["operation": "advertising", "message": error.localizedDescription])
    } else {
      emit("advertising", fields: ["active": true])
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
    guard characteristic.uuid == frameCharacteristicUUID else { return }
    subscribedCentrals[central.identifier] = central
    emit("readyToSend", fields: ["peer": central.identifier.uuidString, "role": "server"])
    pumpSendQueue()
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
    subscribedCentrals.removeValue(forKey: central.identifier)
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for request in requests {
      guard request.characteristic.uuid == frameCharacteristicUUID,
            let value = request.value, !value.isEmpty, value.count <= maxFrameBytes else {
        peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
        continue
      }
      emit("frameReceived", fields: ["peer": request.central.identifier.uuidString, "frame": [UInt8](value)])
      peripheral.respond(to: request, withResult: .success)
    }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    pumpSendQueue()
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}
