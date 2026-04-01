import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_constants.dart';
import '../widgets/result_row.dart';

class PortCheckerScreen extends StatefulWidget {
  const PortCheckerScreen({super.key});

  @override
  State<PortCheckerScreen> createState() => _PortCheckerScreenState();
}

class _PortCheckerScreenState extends State<PortCheckerScreen> {
  final TextEditingController _hostController =
      TextEditingController(text: 'google.com');
  final TextEditingController _portController =
      TextEditingController(text: '443');
  final TextEditingController _timeoutController =
      TextEditingController(text: '3');

  final TextEditingController _newPortLabelController = TextEditingController();
  final TextEditingController _newPortNumberController = TextEditingController();

  // Stores both the result rows AND a separate status string so we can colour it.
  Map<String, String>? _result;
  String? _resultStatus; // 'OPEN' | 'CLOSED' | 'ERROR'
  String? _errorMessage;
  bool _isChecking = false;
  bool _showAddPortForm = false;

  List<Map<String, dynamic>> _customPorts = [];

  static const List<Map<String, dynamic>> _builtInPorts = [
    {'label': 'SSH', 'port': 22},
    {'label': 'HTTP', 'port': 80},
    {'label': 'HTTPS', 'port': 443},
    {'label': 'DNS', 'port': 53},
    {'label': 'RDP', 'port': 3389},
    {'label': 'SMB', 'port': 445},
  ];

  @override
  void initState() {
    super.initState();
    _loadCustomPorts();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _timeoutController.dispose();
    _newPortLabelController.dispose();
    _newPortNumberController.dispose();
    super.dispose();
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _loadCustomPorts() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(AppKeys.savedCustomPorts) ?? [];
    if (!mounted) return;
    setState(() {
      _customPorts = rawList
          .map((item) => Map<String, dynamic>.from(jsonDecode(item) as Map))
          .toList();
    });
  }

  Future<void> _persistCustomPorts(List<Map<String, dynamic>> ports) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      AppKeys.savedCustomPorts,
      ports.map(jsonEncode).toList(),
    );
    if (!mounted) return;
    setState(() => _customPorts = ports);
  }

  // ── Add / delete custom ports ────────────────────────────────────────────────

  Future<void> _saveCustomPort() async {
    final label = _newPortLabelController.text.trim();
    final port = int.tryParse(_newPortNumberController.text.trim());

    if (label.isEmpty) {
      _showSnack('Port label cannot be empty');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      _showSnack('Port must be between 1 and 65535');
      return;
    }

    final exists = _customPorts.any(
      (item) =>
          (item['label'] ?? '').toString().toLowerCase() ==
              label.toLowerCase() &&
          item['port'] == port,
    );
    if (exists) {
      _showSnack('This saved port already exists');
      return;
    }

    await _persistCustomPorts([
      ..._customPorts,
      {'label': label, 'port': port},
    ]);

    _newPortLabelController.clear();
    _newPortNumberController.clear();
    if (!mounted) return;
    setState(() => _showAddPortForm = false);
    _showSnack('Saved port added');
  }

  Future<void> _deleteCustomPort(int index) async {
    final item = _customPorts[index];
    final label = item['label']?.toString() ?? 'this port';
    final port = item['port']?.toString() ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved port?'),
        content: Text('Delete "$label${port.isEmpty ? '' : ' · $port'}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final updated = [..._customPorts]..removeAt(index);
    await _persistCustomPorts(updated);

    if (!mounted) return;
    _showSnack('Saved port deleted');
  }

  // ── Port check ───────────────────────────────────────────────────────────────

  Future<void> _checkPort() async {
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();
    final timeoutText = _timeoutController.text.trim();

    if (host.isEmpty) {
      setState(() {
        _result = null;
        _resultStatus = null;
        _errorMessage = 'Host cannot be empty.';
      });
      return;
    }

    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _result = null;
        _resultStatus = null;
        _errorMessage = 'Port must be between 1 and 65535.';
      });
      return;
    }

    final timeoutSeconds = int.tryParse(timeoutText);
    if (timeoutSeconds == null || timeoutSeconds < 1 || timeoutSeconds > 60) {
      setState(() {
        _result = null;
        _resultStatus = null;
        _errorMessage = 'Timeout must be between 1 and 60 seconds.';
      });
      return;
    }

    setState(() {
      _isChecking = true;
      _result = null;
      _resultStatus = null;
      _errorMessage = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(seconds: timeoutSeconds),
      );
      stopwatch.stop();
      await socket.close();

      if (!mounted) return;
      setState(() {
        _resultStatus = 'OPEN';
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'OPEN',
          'Response Time': '${stopwatch.elapsedMilliseconds} ms',
          'Timeout': '${timeoutSeconds}s',
        };
      });
    } on SocketException catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _resultStatus = 'CLOSED';
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'CLOSED / UNREACHABLE',
          'Details': e.message,
          'Timeout': '${timeoutSeconds}s',
        };
      });
    } catch (e) {
      // HandshakeException and any other unexpected errors land here.
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _resultStatus = 'ERROR';
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'ERROR',
          'Details': e.toString(),
          'Timeout': '${timeoutSeconds}s',
        };
      });
    } finally {
      // Always clear the loading state, even if the widget was disposed.
      if (mounted) setState(() => _isChecking = false);
    }
  }

  // ── Copy ─────────────────────────────────────────────────────────────────────

  Future<void> _copyResult() async {
    if (_result == null || _result!.isEmpty) return;

    final text = _result!.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;
    _showSnack('Result copied to clipboard');
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _setPort(int port) => _portController.text = port.toString();

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'OPEN':
        return AppColors.statusOpen;
      case 'CLOSED':
        return AppColors.statusClosed;
      default:
        return AppColors.statusError;
    }
  }

  // ── Widget builders ──────────────────────────────────────────────────────────

  Widget _buildBuiltInPorts() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _builtInPorts
          .map(
            (item) => ActionChip(
              label: Text('${item['label']} · ${item['port']}'),
              onPressed: () => _setPort(item['port'] as int),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSavedPorts() {
    if (_customPorts.isEmpty) {
      return Text(
        'No saved ports yet.',
        style: TextStyle(fontSize: 14, color: AppColors.textSubtle),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_customPorts.length, (index) {
        final item = _customPorts[index];
        final label = item['label']?.toString() ?? 'Port';
        final port = item['port']?.toString() ?? '';

        return InputChip(
          label: Text('$label · $port'),
          onPressed: () {
            final parsed = int.tryParse(port);
            if (parsed != null) _setPort(parsed);
          },
          onDeleted: () => _deleteCustomPort(index),
        );
      }),
    );
  }

  Widget _buildAddPortForm() {
    if (!_showAddPortForm) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newPortLabelController,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      hintText: 'MySQL',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _newPortNumberController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '3306',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveCustomPort,
                child: const Text('Save Port'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultContent() {
    if (_errorMessage != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Error: $_errorMessage',
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      );
    }

    if (_result == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Enter host and port, then press Check Port.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      );
    }

    final entries = _result!.entries.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Result',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy result',
                  onPressed: _copyResult,
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < entries.length; i++) ...[
              ResultRow(
                label: entries[i].key,
                value: entries[i].value,
                // Colour the "Status" row value for quick visual feedback.
                valueColor: entries[i].key == 'Status'
                    ? _statusColor(_resultStatus)
                    : null,
              ),
              if (i < entries.length - 1) const Divider(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Port Checker')),
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
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host or IP',
                  hintText: 'example.com or 192.168.1.1',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '443',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _timeoutController,
                      decoration: const InputDecoration(
                        labelText: 'Timeout',
                        hintText: '3',
                        suffixText: 's',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('Built-in Ports'),
              const SizedBox(height: 8),
              _buildBuiltInPorts(),
              const SizedBox(height: 16),
              _buildSectionTitle(
                'Saved Ports',
                trailing: TextButton.icon(
                  onPressed: () =>
                      setState(() => _showAddPortForm = !_showAddPortForm),
                  icon: Icon(
                    _showAddPortForm ? Icons.close : Icons.add,
                    size: 18,
                  ),
                  label: Text(_showAddPortForm ? 'Cancel' : 'Add'),
                ),
              ),
              const SizedBox(height: 8),
              _buildSavedPorts(),
              if (_showAddPortForm) ...[
                const SizedBox(height: 12),
                _buildAddPortForm(),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isChecking ? null : _checkPort,
                child: Text(_isChecking ? 'Checking…' : 'Check Port'),
              ),
              const SizedBox(height: 24),
              _buildResultContent(),
            ],
          ),
        ),
      ),
    );
  }
}
