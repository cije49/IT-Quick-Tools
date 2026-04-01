import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_constants.dart';

class WifiQrScreen extends StatefulWidget {
  const WifiQrScreen({super.key});

  @override
  State<WifiQrScreen> createState() => _WifiQrScreenState();
}

class _WifiQrScreenState extends State<WifiQrScreen> {
  final TextEditingController _ssidController =
      TextEditingController(text: 'MyWiFi');
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _security = 'WPA';
  String _qrData = '';
  bool _obscurePassword = true;
  bool _showQrCard = true;
  bool _showPasswordInCard = false;

  List<Map<String, String>> _savedProfiles = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSavedProfiles();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _loadSavedProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(AppKeys.savedWifiProfiles) ?? [];
    if (!mounted) return;
    setState(() {
      _savedProfiles = rawList
          .map((item) => Map<String, String>.from(jsonDecode(item) as Map))
          .toList();
    });
  }

  Future<void> _persistProfiles(List<Map<String, String>> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        AppKeys.savedWifiProfiles, profiles.map(jsonEncode).toList());
    if (!mounted) return;
    setState(() => _savedProfiles = profiles);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _securityLabel(String v) {
    switch (v) {
      case 'WPA': return 'WPA/WPA2';
      case 'WEP': return 'WEP';
      case 'nopass': return 'Open';
      default: return v;
    }
  }

  Color _securityColor(String v) {
    switch (v) {
      case 'WPA': return AppColors.statusOpen;
      case 'WEP': return AppColors.statusError;
      case 'nopass': return AppColors.statusClosed;
      default: return AppColors.textSubtle;
    }
  }

  String _defaultDuplicateLabel(String ssid) {
    final existing = _savedProfiles.map((i) => (i['label'] ?? '').trim()).toSet();
    var counter = 2;
    var candidate = '$ssid ($counter)';
    while (existing.contains(candidate)) { counter++; candidate = '$ssid ($counter)'; }
    return candidate;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── QR generation ────────────────────────────────────────────────────────────

  void _generateQr() {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) { setState(() => _qrData = ''); _showSnack('SSID cannot be empty'); return; }
    final password = _passwordController.text.trim();
    final qr = _security == 'nopass'
        ? 'WIFI:T:nopass;S:$ssid;;'
        : 'WIFI:T:$_security;S:$ssid;P:$password;;';
    setState(() { _qrData = qr; _showQrCard = true; _showPasswordInCard = false; });
  }

  void _loadProfile(Map<String, String> profile) {
    setState(() {
      _ssidController.text = profile['ssid'] ?? '';
      _passwordController.text = profile['password'] ?? '';
      _security = profile['security'] ?? 'WPA';
      _obscurePassword = true;
      _showPasswordInCard = false;
    });
    _generateQr();
  }

  void _openFullScreenQr() {
    if (_qrData.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        _FullScreenQrView(
          qrData: _qrData,
          title: _ssidController.text.trim(),
          securityLabel: _securityLabel(_security),
        )));
  }

  // ── Save / edit / delete ─────────────────────────────────────────────────────

  Future<void> _saveCurrentProfile() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();
    if (ssid.isEmpty) { _showSnack('SSID cannot be empty'); return; }

    final exactMatch = _savedProfiles.any((i) =>
        (i['ssid'] ?? '') == ssid &&
        (i['password'] ?? '') == password &&
        (i['security'] ?? '') == _security);
    if (exactMatch) { _showSnack('This profile is already saved'); return; }

    final sameSsidIdx = _savedProfiles.indexWhere((i) => (i['ssid'] ?? '') == ssid);

    if (sameSsidIdx != -1) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('SSID already exists'),
          content: Text('A profile with SSID "$ssid" exists. Update it or save a duplicate?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(ctx).pop('duplicate'), child: const Text('Duplicate')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop('update'), child: const Text('Update')),
          ],
        ),
      );
      if (action == 'update') {
        final existing = _savedProfiles[sameSsidIdx];
        final updated = [..._savedProfiles];
        updated[sameSsidIdx] = {
          'label': (existing['label'] ?? ssid).trim().isEmpty ? ssid : (existing['label'] ?? ssid),
          'ssid': ssid, 'password': password, 'security': _security,
        };
        await _persistProfiles(updated);
        if (!mounted) return;
        _showSnack('Profile updated');
        return;
      }
      if (action == 'duplicate') {
        final autoLabel = _defaultDuplicateLabel(ssid);
        await _persistProfiles([..._savedProfiles,
            {'label': autoLabel, 'ssid': ssid, 'password': password, 'security': _security}]);
        if (!mounted) return;
        _showSnack('Saved as "$autoLabel"');
        return;
      }
      return;
    }

    await _persistProfiles([..._savedProfiles,
        {'label': ssid, 'ssid': ssid, 'password': password, 'security': _security}]);
    if (!mounted) return;
    _showSnack('Profile saved');
  }

  Future<void> _editProfile(int index) async {
    final profile = _savedProfiles[index];
    final labelCtrl = TextEditingController(text: profile['label'] ?? profile['ssid'] ?? '');
    final ssidCtrl  = TextEditingController(text: profile['ssid'] ?? '');
    final passCtrl  = TextEditingController(text: profile['password'] ?? '');
    String sec = profile['security'] ?? 'WPA';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        title: const Text('Edit profile'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Label')),
            const SizedBox(height: 12),
            TextField(controller: ssidCtrl,
                decoration: const InputDecoration(labelText: 'SSID')),
            const SizedBox(height: 12),
            TextField(controller: passCtrl, enabled: sec != 'nopass',
                decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: sec,
              items: const [
                DropdownMenuItem(value: 'WPA', child: Text('WPA/WPA2')),
                DropdownMenuItem(value: 'WEP', child: Text('WEP')),
                DropdownMenuItem(value: 'nopass', child: Text('Open')),
              ],
              onChanged: (v) { if (v != null) ss(() => sec = v); },
              decoration: const InputDecoration(labelText: 'Security'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final label = labelCtrl.text.trim();
              final ssid = ssidCtrl.text.trim();
              if (label.isEmpty || ssid.isEmpty) return;
              Navigator.of(ctx).pop({
                'label': label, 'ssid': ssid,
                'password': passCtrl.text.trim(), 'security': sec,
              });
            },
            child: const Text('Save'),
          ),
        ],
      )),
    );

    labelCtrl.dispose(); ssidCtrl.dispose(); passCtrl.dispose();
    if (result == null) return;
    final updated = [..._savedProfiles];
    updated[index] = result;
    await _persistProfiles(updated);
    if (!mounted) return;
    _showSnack('Profile updated');
  }

  Future<void> _confirmDeleteProfile(int index) async {
    final label = _savedProfiles[index]['label'] ??
        _savedProfiles[index]['ssid'] ?? 'this profile';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('Delete "$label"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    final updated = [..._savedProfiles]..removeAt(index);
    await _persistProfiles(updated);
    if (!mounted) return;
    _showSnack('Profile deleted');
  }

  List<Map<String, String>> _filteredProfiles() {
    if (_searchQuery.isEmpty) return _savedProfiles;
    return _savedProfiles.where((p) {
      final label = (p['label'] ?? '').toLowerCase();
      final ssid  = (p['ssid']  ?? '').toLowerCase();
      return label.contains(_searchQuery) || ssid.contains(_searchQuery);
    }).toList();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isOpen = _security == 'nopass';

    return Scaffold(
      appBar: AppBar(title: const Text('WiFi QR')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFormCard(isOpen),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _generateQr,
                      icon: const Icon(Icons.qr_code_rounded, size: 18),
                      label: const Text('Generate QR'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saveCurrentProfile,
                      icon: const Icon(Icons.bookmark_outline_rounded, size: 18),
                      label: const Text('Save Profile'),
                    ),
                  ),
                ],
              ),
              if (_qrData.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildQrCard(),
              ],
              const SizedBox(height: 24),
              _buildProfilesSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard(bool isOpen) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _ssidController,
              decoration: InputDecoration(
                labelText: 'Network name (SSID)',
                prefixIcon: Icon(Icons.wifi_rounded, size: 18, color: AppColors.textSubtle),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              enabled: !isOpen,
              decoration: InputDecoration(
                labelText: isOpen ? 'Password (open network)' : 'Password',
                prefixIcon:
                    Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textSubtle),
                suffixIcon: !isOpen
                    ? IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _security,
              items: const [
                DropdownMenuItem(value: 'WPA', child: Text('WPA / WPA2')),
                DropdownMenuItem(value: 'WEP', child: Text('WEP (legacy)')),
                DropdownMenuItem(value: 'nopass', child: Text('Open (no password)')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() { _security = v; _obscurePassword = true; });
              },
              decoration: InputDecoration(
                labelText: 'Security',
                prefixIcon:
                    Icon(Icons.shield_outlined, size: 18, color: AppColors.textSubtle),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCard() {
    final password = _passwordController.text;
    final hasPass = _security != 'nopass' && password.isNotEmpty;
    final passDisplay = _security == 'nopass'
        ? 'No password'
        : password.isEmpty
            ? 'Empty'
            : (_showPasswordInCard ? password : '••••••••');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Text('QR Code',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openFullScreenQr,
                  icon: const Icon(Icons.open_in_full_rounded, size: 14),
                  label: const Text('Fullscreen'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _qrData = ''),
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // QR itself
            GestureDetector(
              onTap: _openFullScreenQr,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: _qrData,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Info pills
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _infoPill(Icons.wifi_rounded, _ssidController.text.trim()),
                const SizedBox(width: 8),
                _infoPill(
                  Icons.shield_outlined,
                  _securityLabel(_security),
                  color: _securityColor(_security),
                ),
              ],
            ),
            if (hasPass) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _infoPill(Icons.lock_outline_rounded, passDisplay),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(
                        () => _showPasswordInCard = !_showPasswordInCard),
                    child: Text(
                      _showPasswordInCard ? 'Hide' : 'Show',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoPill(IconData icon, String label, {Color? color}) {
    final c = color ?? AppColors.textSubtle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }

  Widget _buildProfilesSection() {
    final filtered = _filteredProfiles();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Saved Profiles',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted),
            ),
            const Spacer(),
            if (_savedProfiles.isNotEmpty)
              Text(
                '${_savedProfiles.length}',
                style: TextStyle(fontSize: 13, color: AppColors.textSubtle),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_savedProfiles.isNotEmpty) ...[
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name or SSID…',
              prefixIcon:
                  Icon(Icons.search, size: 18, color: AppColors.textSubtle),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_savedProfiles.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.textSubtle),
                const SizedBox(height: 12),
                Text('No saved profiles yet',
                    style: TextStyle(color: AppColors.textSubtle)),
              ]),
            ),
          )
        else if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No profiles match "$_searchQuery"',
                  style: TextStyle(color: AppColors.textSubtle)),
            ),
          )
        else
          Card(
            child: Column(
              children: List.generate(filtered.length, (i) {
                final profile = filtered[i];
                final origIdx = _savedProfiles.indexOf(profile);
                final label = (profile['label'] ?? profile['ssid'] ?? '').trim();
                final ssid  = (profile['ssid'] ?? '').trim();
                final sec   = profile['security'] ?? 'WPA';
                final isLast = i == filtered.length - 1;

                return Column(children: [
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _securityColor(sec).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.wifi_rounded,
                          size: 20, color: _securityColor(sec)),
                    ),
                    title: Text(label.isEmpty ? ssid : label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Row(children: [
                      if (ssid != label && label.isNotEmpty)
                        Text('$ssid  ·  ',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSubtle)),
                      _securityBadge(sec),
                    ]),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _editProfile(origIdx),
                        tooltip: 'Edit',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _confirmDeleteProfile(origIdx),
                        tooltip: 'Delete',
                        visualDensity: VisualDensity.compact,
                      ),
                    ]),
                    onTap: () => _loadProfile(profile),
                  ),
                  if (!isLast)
                    Divider(height: 1, indent: 16, endIndent: 16,
                        color: AppColors.borderDefault),
                ]);
              }),
            ),
          ),
      ],
    );
  }

  Widget _securityBadge(String sec) {
    final color = _securityColor(sec);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _securityLabel(sec),
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ── Full-screen QR ────────────────────────────────────────────────────────────

class _FullScreenQrView extends StatelessWidget {
  const _FullScreenQrView({
    required this.qrData,
    required this.title,
    required this.securityLabel,
  });

  final String qrData;
  final String title;
  final String securityLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title.isEmpty ? 'WiFi QR' : title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                  color: Colors.black.withValues(alpha: 0.12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_rounded, size: 32,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 10),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(securityLabel,
                    style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 20),
                QrImageView(
                  data: qrData,
                  size: 300,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black),
                ),
                const SizedBox(height: 16),
                const Text('Scan to connect',
                    style: TextStyle(color: Colors.black38, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
