// ignore_for_file: use_build_context_synchronously

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'contact_qr_scanner_page.dart';
import '../../core/security/contact_identity.dart';
import '../../core/security/contact_key_change.dart';
import '../../core/security/identity_vault.dart';
import '../../core/security/secure_message.dart';

class IdentityContactsPage extends StatefulWidget {
  const IdentityContactsPage({super.key, this.vault});

  final IdentityVault? vault;

  @override
  State<IdentityContactsPage> createState() => _IdentityContactsPageState();
}

class _IdentityContactsPageState extends State<IdentityContactsPage> {
  late final IdentityVault _vault = widget.vault ?? IdentityVault();
  IdentityKeyMaterial? _identity;
  List<VerifiedInLinkContact> _contacts = <VerifiedInLinkContact>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final identity = await _vault.loadOrCreateIdentity();
      final contacts = await _vault.listVerifiedContacts();
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _contacts = contacts;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _showMyIdentity() async {
    final identity = _identity;
    if (identity == null) return;
    final bundle = jsonEncode(identity.publicBundleJson());
    final fingerprint = await identity.fingerprint();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your public identity'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(data: bundle, size: 220),
              const SizedBox(height: 12),
              const Text('Share this QR code. It contains public keys only.'),
              const SizedBox(height: 12),
              const Align(alignment: Alignment.centerLeft, child: Text('Fingerprint')),
              SelectableText(fingerprint),
              const SizedBox(height: 8),
              SelectableText(bundle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _scanBundle() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const ContactQrScannerPage(),
      ),
    );
    if (!mounted || scanned == null || scanned.isEmpty) return;
    // The QR contents are untrusted input. They are only placed in the import
    // field; parse/validation and independent fingerprint verification still apply.
    await _importBundleDialog(initialBundle: scanned);
  }

  Future<void> _importBundleDialog({String initialBundle = ''}) async {
    final controller = TextEditingController(text: initialBundle);
    final nameController = TextEditingController();
    final fingerprintController = TextEditingController();
    String? importError;
    InLinkPublicContact? imported;
    String? fingerprint;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add verified contact'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Import public keys, then compare the fingerprint with this person '
                    'over a separate trusted channel before saving.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final scanned = await Navigator.of(dialogContext).push<String>(
                        MaterialPageRoute<String>(
                          builder: (_) => const ContactQrScannerPage(),
                        ),
                      );
                      if (scanned == null || !dialogContext.mounted) return;
                      setDialogState(() {
                        controller.text = scanned;
                        imported = null;
                        fingerprint = null;
                        importError = null;
                      });
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR code'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Public bundle JSON',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      setDialogState(() {
                        imported = null;
                        fingerprint = null;
                        importError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () async {
                      try {
                        final parsed = InLinkPublicContact.parseBundle(controller.text.trim());
                        final fp = await parsed.fingerprint();
                        setDialogState(() {
                          imported = parsed;
                          fingerprint = fp;
                          importError = null;
                        });
                      } catch (error) {
                        setDialogState(() => importError = error.toString());
                      }
                    },
                    child: const Text('Inspect public bundle'),
                  ),
                  if (importError != null) ...[
                    const SizedBox(height: 8),
                    Text(importError!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  if (fingerprint != null) ...[
                    const SizedBox(height: 12),
                    const Text('Compare this fingerprint with the contact over a separate trusted channel.'),
                    SelectableText(fingerprint!, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Contact display name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: fingerprintController,
                      decoration: const InputDecoration(
                        labelText: 'Fingerprint confirmed out of band',
                        hintText: 'Paste the fingerprint after comparing it',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: imported == null
                  ? null
                  : () async {
                      try {
                        final verified = await imported!.verifyFingerprint(
                          displayName: nameController.text,
                          fingerprintEnteredByUser: fingerprintController.text,
                        );
                        if (hasDifferentKeyForSameName(
                          existingContacts: _contacts,
                          candidate: verified,
                        )) {
                          final proceed = await showDialog<bool>(
                            context: dialogContext,
                            builder: (warningContext) => AlertDialog(
                              title: const Text('Identity key changed'),
                              content: Text(
                                'A contact named "${verified.displayName}" already exists '
                                'with a different verified fingerprint. This may mean a key '
                                'change, a mistaken name, or an impersonation attempt. '
                                'The existing contact will not be replaced. If you verified '
                                'this new fingerprint independently, save it as a separate contact '
                                'with a different name.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(warningContext, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(warningContext, true),
                                  child: const Text('Save separately'),
                                ),
                              ],
                            ),
                          );
                          if (proceed != true) return;
                          setDialogState(() => importError =
                              'Choose a different display name to preserve the existing identity.');
                          return;
                        }
                        await _vault.saveVerifiedContact(verified);
                        await _load();
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        setDialogState(() => importError = error.toString());
                      }
                    },
              child: const Text('Verify and save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    nameController.dispose();
    fingerprintController.dispose();
  }

  Future<void> _deleteContact(VerifiedInLinkContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('Remove ${contact.displayName} from this device’s verified contacts?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _vault.deleteVerifiedContact(contact.fingerprint);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Identity & contacts')),
      body: _error != null
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                const Text('Could not load identity storage'),
                SelectableText(_error!),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.fingerprint),
                    title: const Text('Your pseudonymous identity'),
                    subtitle: const Text('Share only your public identity bundle'),
                    trailing: const Icon(Icons.qr_code_2),
                    onTap: _showMyIdentity,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('Verified contacts', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Add contact',
                      icon: const Icon(Icons.person_add_alt_1),
                      onSelected: (choice) {
                        if (choice == 'scan') {
                          _scanBundle();
                        } else {
                          _importBundleDialog();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'scan',
                          child: ListTile(
                            leading: Icon(Icons.qr_code_scanner),
                            title: Text('Scan QR code'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'paste',
                          child: ListTile(
                            leading: Icon(Icons.content_paste),
                            title: Text('Paste public bundle'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_contacts.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No verified contacts yet. Scan a QR code or paste a public bundle, then compare its fingerprint before saving.'),
                    ),
                  )
                else
                  ..._contacts.map(
                    (contact) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.verified_user)),
                        title: Text(contact.displayName),
                        subtitle: Text(
                          'Verified fingerprint: ${contact.fingerprint}',
                          maxLines: 2,
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove contact',
                          onPressed: () => _deleteContact(contact),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Trust warning: importing a bundle or scanning a QR code does not prove who owns the key. Compare fingerprints in person or through another trusted channel before saving a contact.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
