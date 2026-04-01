import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WifiQrScreen extends StatefulWidget {
  const WifiQrScreen({super.key});

  @override
  State<WifiQrScreen> createState() => _WifiQrScreenState();
}

class _WifiQrScreenState extends State<WifiQrScreen> {
  static const String _savedProfilesKey = 'saved_wifi_profiles';

  final TextEditingController _ssidController =
      TextEditingController(text: 'MyWiFi');
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _security = 'WPA';
  String _qrData = '';
  bool _showPassword = false;
  bool _showQrCard = true;

  List<Map<String, String>> _savedProfiles = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSavedProfiles();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_savedProfilesKey) ?? [];

    if (!mounted) return;

    setState(() {
      _savedProfiles = rawList
          .map((item) => Map<String, String>.from(jsonDecode(item)))
          .toList();
    });
  }

  Future<void> _persistProfiles(List<Map<String, String>> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _savedProfilesKey,
      profiles.map((item) => jsonEncode(item)).toList(),
    );

    if (!mounted) return;

    setState(() {
      _savedProfiles = profiles;
    });
  }

  String _securityLabel(String value) {
    switch (value) {
      case 'WPA':
        return 'WPA/WPA2';
      case 'WEP':
        return 'WEP';
      case 'nopass':
        return 'Open';
      default:
        return value;
    }
  }

  String _passwordDisplay() {
    if (_security == 'nopass') {
      return 'No password';
    }

    final password = _passwordController.text;
    if (password.isEmpty) {
      return 'Empty';
    }

    return _showPassword ? password : '••••••••';
  }

  String _defaultDuplicateLabel(String ssid) {
    final existingLabels = _savedProfiles
        .map((item) => (item['label'] ?? '').trim())
        .toSet();

    var counter = 2;
    var candidate = '$ssid ($counter)';

    while (existingLabels.contains(candidate)) {
      counter++;
      candidate = '$ssid ($counter)';
    }

    return candidate;
  }

  void _generateQr() {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();

    if (ssid.isEmpty) {
      setState(() {
        _qrData = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SSID cannot be empty')),
      );
      return;
    }

    final qr = _security == 'nopass'
        ? 'WIFI:T:nopass;S:$ssid;;'
        : 'WIFI:T:$_security;S:$ssid;P:$password;;';

    setState(() {
      _qrData = qr;
      _showQrCard = true;
    });
  }

  void _hideQrCard() {
    setState(() {
      _showQrCard = false;
    });
  }

  void _loadProfile(Map<String, String> profile) {
    setState(() {
      _ssidController.text = profile['ssid'] ?? '';
      _passwordController.text = profile['password'] ?? '';
      _security = profile['security'] ?? 'WPA';
      _showPassword = false;
    });

    _generateQr();
  }

  void _openFullScreenQr() {
    if (_qrData.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenQrView(
          qrData: _qrData,
          title: _ssidController.text.trim(),
          securityLabel: _securityLabel(_security),
        ),
      ),
    );
  }

  Future<void> _saveCurrentProfile() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();

    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SSID cannot be empty')),
      );
      return;
    }

    final exactMatchExists = _savedProfiles.any(
      (item) =>
          (item['ssid'] ?? '') == ssid &&
          (item['password'] ?? '') == password &&
          (item['security'] ?? '') == _security,
    );

    if (exactMatchExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This WiFi profile is already saved')),
      );
      return;
    }

    final sameSsidIndex = _savedProfiles.indexWhere(
      (item) => (item['ssid'] ?? '') == ssid,
    );

    if (sameSsidIndex != -1) {
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('SSID already exists'),
            content: Text(
              'A saved profile already uses SSID "$ssid". Do you want to update the existing profile or save a duplicate with a new profile label?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('duplicate'),
                child: const Text('Save Duplicate'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop('update'),
                child: const Text('Update Existing'),
              ),
            ],
          );
        },
      );

      if (action == 'update') {
        final existing = _savedProfiles[sameSsidIndex];
        final updated = [..._savedProfiles];
        updated[sameSsidIndex] = {
          'label': (existing['label'] ?? ssid).trim().isEmpty
              ? ssid
              : (existing['label'] ?? ssid),
          'ssid': ssid,
          'password': password,
          'security': _security,
        };

        await _persistProfiles(updated);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Existing WiFi profile updated')),
        );
        return;
      }

      if (action == 'duplicate') {
        final autoLabel = _defaultDuplicateLabel(ssid);

        final updated = [
          ..._savedProfiles,
          {
            'label': autoLabel,
            'ssid': ssid,
            'password': password,
            'security': _security,
          }
        ];

        await _persistProfiles(updated);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicate WiFi profile saved as "$autoLabel"')),
        );
        return;
      }

      return;
    }

    final updated = [
      ..._savedProfiles,
      {
        'label': ssid,
        'ssid': ssid,
        'password': password,
        'security': _security,
      }
    ];

    await _persistProfiles(updated);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WiFi profile saved')),
    );
  }

  Future<void> _editProfile(int index) async {
    final profile = _savedProfiles[index];

    final labelController =
        TextEditingController(text: profile['label'] ?? profile['ssid'] ?? '');
    final ssidController =
        TextEditingController(text: profile['ssid'] ?? '');
    final passwordController =
        TextEditingController(text: profile['password'] ?? '');
    String selectedSecurity = profile['security'] ?? 'WPA';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Profile label',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ssidController,
                  decoration: const InputDecoration(
                    labelText: 'SSID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedSecurity,
                  items: const [
                    DropdownMenuItem(value: 'WPA', child: Text('WPA/WPA2')),
                    DropdownMenuItem(value: 'WEP', child: Text('WEP')),
                    DropdownMenuItem(value: 'nopass', child: Text('Open')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    selectedSecurity = value;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Security',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final label = labelController.text.trim();
                final ssid = ssidController.text.trim();
                final password = passwordController.text.trim();

                if (label.isEmpty || ssid.isEmpty) return;

                Navigator.of(dialogContext).pop({
                  'label': label,
                  'ssid': ssid,
                  'password': password,
                  'security': selectedSecurity,
                });
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    labelController.dispose();
    ssidController.dispose();
    passwordController.dispose();

    if (result == null) return;

    final updated = [..._savedProfiles];
    updated[index] = result;

    await _persistProfiles(updated);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
  }

  Future<void> _confirmDeleteProfile(int index) async {
    final profile = _savedProfiles[index];
    final label = profile['label'] ?? profile['ssid'] ?? 'this profile';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete profile?'),
          content: Text(
            'Are you sure you want to delete "$label"? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final updatedProfiles = [..._savedProfiles]..removeAt(index);
    await _persistProfiles(updatedProfiles);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WiFi profile deleted')),
    );
  }

  List<Map<String, String>> _filteredProfiles() {
    if (_searchQuery.isEmpty) return _savedProfiles;

    return _savedProfiles.where((profile) {
      final label = (profile['label'] ?? '').toLowerCase();
      final ssid = (profile['ssid'] ?? '').toLowerCase();
      final security = (profile['security'] ?? '').toLowerCase();

      return label.contains(_searchQuery) ||
          ssid.contains(_searchQuery) ||
          security.contains(_searchQuery);
    }).toList();
  }

  Widget _buildQrSection(BuildContext context) {
    if (_qrData.isEmpty || !_showQrCard) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Close QR card',
                onPressed: _hideQrCard,
                icon: const Icon(Icons.close),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _openFullScreenQr,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.wifi,
                      size: 28,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ssidController.text.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _securityLabel(_security),
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: QrImageView(
                        data: _qrData,
                        size: 220,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Tap to open fullscreen',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _InfoRow(
              label: 'SSID',
              value: _ssidController.text.trim(),
            ),
            const Divider(height: 24),
            _InfoRow(
              label: 'Security',
              value: _securityLabel(_security),
            ),
            const Divider(height: 24),
            _InfoRow(
              label: 'Password',
              value: _passwordDisplay(),
            ),
            if (_security != 'nopass' && _passwordController.text.isNotEmpty) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showPassword = !_showPassword;
                    });
                  },
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  label: Text(_showPassword ? 'Hide Password' : 'Show Password'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSavedProfilesSection() {
    final filteredProfiles = _filteredProfiles();

    if (_savedProfiles.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No saved WiFi profiles yet.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      );
    }

    if (filteredProfiles.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No saved profiles match your search.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: List.generate(filteredProfiles.length, (index) {
            final profile = filteredProfiles[index];
            final originalIndex = _savedProfiles.indexOf(profile);
            final isLast = index == filteredProfiles.length - 1;
            final label = (profile['label'] ?? profile['ssid'] ?? '').trim();
            final ssid = (profile['ssid'] ?? '').trim();

            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.wifi_outlined),
                  title: Text(label.isEmpty ? ssid : label),
                  subtitle: Text(
                    ssid == label || label.isEmpty
                        ? _securityLabel(profile['security'] ?? 'WPA')
                        : '$ssid • ${_securityLabel(profile['security'] ?? 'WPA')}',
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        tooltip: 'Edit profile',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editProfile(originalIndex),
                      ),
                      IconButton(
                        tooltip: 'Delete profile',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDeleteProfile(originalIndex),
                      ),
                    ],
                  ),
                  onTap: () => _loadProfile(profile),
                ),
                if (!isLast) const Divider(height: 1),
              ],
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _security == 'nopass';

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi QR Generator'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ssidController,
                decoration: const InputDecoration(
                  labelText: 'SSID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                enabled: !isOpen,
                decoration: InputDecoration(
                  labelText: isOpen ? 'Password (not used for open network)' : 'Password',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _security,
                items: const [
                  DropdownMenuItem(value: 'WPA', child: Text('WPA/WPA2')),
                  DropdownMenuItem(value: 'WEP', child: Text('WEP')),
                  DropdownMenuItem(value: 'nopass', child: Text('Open')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _security = value;
                    _showPassword = false;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Security',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _generateQr,
                      child: const Text('Generate QR'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saveCurrentProfile,
                      child: const Text('Save Profile'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildQrSection(context),
              if (_qrData.isNotEmpty && !_showQrCard) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showQrCard = true;
                      });
                    },
                    icon: const Icon(Icons.qr_code_2_outlined),
                    label: const Text('Show QR again'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Saved Profiles',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search saved profiles',
                  hintText: 'Search by label or SSID',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _buildSavedProfilesSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: SelectableText(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _FullScreenQrView extends StatelessWidget {
  final String qrData;
  final String title;
  final String securityLabel;

  const _FullScreenQrView({
    required this.qrData,
    required this.title,
    required this.securityLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? 'WiFi QR' : title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                  color: Colors.black.withValues(alpha: 0.12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi,
                  size: 30,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  securityLabel,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                QrImageView(
                  data: qrData,
                  size: 320,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}