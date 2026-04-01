import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PortCheckerScreen extends StatefulWidget {
  const PortCheckerScreen({super.key});

  @override
  State<PortCheckerScreen> createState() => _PortCheckerScreenState();
}

class _PortCheckerScreenState extends State<PortCheckerScreen> {
  static const String _savedCustomPortsKey = 'saved_custom_ports';

  final TextEditingController _hostController =
      TextEditingController(text: 'google.com');
  final TextEditingController _portController =
      TextEditingController(text: '443');
  final TextEditingController _timeoutController =
      TextEditingController(text: '3');

  final TextEditingController _newPortLabelController = TextEditingController();
  final TextEditingController _newPortNumberController = TextEditingController();

  Map<String, String>? _result;
  String? _errorMessage;
  bool _isChecking = false;
  bool _showAddPortForm = false;

  List<Map<String, dynamic>> _customPorts = [];

  final List<Map<String, dynamic>> _builtInPorts = const [
    {'label': 'SSH', 'port': 22},
    {'label': 'HTTP', 'port': 80},
    {'label': 'HTTPS', 'port': 443},
    {'label': 'RDP', 'port': 3389},
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

  Future<void> _loadCustomPorts() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_savedCustomPortsKey) ?? [];

    if (!mounted) return;

    setState(() {
      _customPorts = rawList
          .map((item) => Map<String, dynamic>.from(jsonDecode(item)))
          .toList();
    });
  }

  Future<void> _persistCustomPorts(List<Map<String, dynamic>> ports) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _savedCustomPortsKey,
      ports.map((item) => jsonEncode(item)).toList(),
    );

    if (!mounted) return;

    setState(() {
      _customPorts = ports;
    });
  }

  Future<void> _saveCustomPort() async {
    final label = _newPortLabelController.text.trim();
    final port = int.tryParse(_newPortNumberController.text.trim());

    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Port label cannot be empty')),
      );
      return;
    }

    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Port must be between 1 and 65535')),
      );
      return;
    }

    final exists = _customPorts.any(
      (item) =>
          (item['label'] ?? '').toString().toLowerCase() == label.toLowerCase() &&
          item['port'] == port,
    );

    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This saved port already exists')),
      );
      return;
    }

    final updated = [
      ..._customPorts,
      {
        'label': label,
        'port': port,
      }
    ];

    await _persistCustomPorts(updated);

    _newPortLabelController.clear();
    _newPortNumberController.clear();

    if (!mounted) return;

    setState(() {
      _showAddPortForm = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved port added')),
    );
  }

  Future<void> _deleteCustomPort(int index) async {
    final item = _customPorts[index];
    final label = item['label']?.toString() ?? 'this port';
    final port = item['port']?.toString() ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete saved port?'),
          content: Text('Delete "$label${port.isEmpty ? '' : ' · $port'}"?'),
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

    final updated = [..._customPorts]..removeAt(index);
    await _persistCustomPorts(updated);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved port deleted')),
    );
  }

  Future<void> _checkPort() async {
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();
    final timeoutText = _timeoutController.text.trim();

    if (host.isEmpty) {
      setState(() {
        _result = null;
        _errorMessage = 'Host cannot be empty.';
      });
      return;
    }

    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _result = null;
        _errorMessage = 'Port must be between 1 and 65535.';
      });
      return;
    }

    final timeoutSeconds = int.tryParse(timeoutText);
    if (timeoutSeconds == null || timeoutSeconds < 1 || timeoutSeconds > 60) {
      setState(() {
        _result = null;
        _errorMessage = 'Timeout must be between 1 and 60 seconds.';
      });
      return;
    }

    setState(() {
      _isChecking = true;
      _result = null;
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
      final elapsedMs = stopwatch.elapsedMilliseconds;

      await socket.close();

      setState(() {
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'OPEN',
          'Response Time': '$elapsedMs ms',
          'Timeout': '${timeoutSeconds}s',
        };
      });
    } on SocketException catch (e) {
      stopwatch.stop();
      setState(() {
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'CLOSED / UNREACHABLE',
          'Details': e.message,
          'Timeout': '${timeoutSeconds}s',
        };
      });
    } on HandshakeException catch (e) {
      stopwatch.stop();
      setState(() {
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'ERROR',
          'Details': e.toString(),
          'Timeout': '${timeoutSeconds}s',
        };
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'ERROR',
          'Details': e.toString(),
          'Timeout': '${timeoutSeconds}s',
        };
      });
    } finally {
      setState(() {
        _isChecking = false;
      });
    }
  }

  Future<void> _copyResult() async {
    if (_result == null || _result!.isEmpty) return;

    final text = _result!.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Result copied to clipboard')),
    );
  }

  void _setPort(int port) {
    _portController.text = port.toString();
  }

  Widget _buildBuiltInPorts() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _builtInPorts.map((item) {
        return ActionChip(
          label: Text('${item['label']} · ${item['port']}'),
          onPressed: () => _setPort(item['port'] as int),
        );
      }).toList(),
    );
  }

  Widget _buildSavedPorts() {
    if (_customPorts.isEmpty) {
      return const Text(
        'No saved ports yet.',
        style: TextStyle(
          fontSize: 14,
          color: Colors.white54,
        ),
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
            if (parsed != null) {
              _setPort(parsed);
            }
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
                      border: OutlineInputBorder(),
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
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveCustomPort,
                    child: const Text('Save Port'),
                  ),
                ),
              ],
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
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
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
            ..._result!.entries.map((entry) {
              final isLast = entry.key == _result!.keys.last;

              return Column(
                children: [
                  _ResultRow(
                    label: entry.key,
                    value: entry.value,
                  ),
                  if (!isLast) const Divider(height: 24),
                ],
              );
            }),
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
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
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
      appBar: AppBar(
        title: const Text('Port Checker'),
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
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host or IP',
                  hintText: 'example.com or 192.168.1.1',
                  border: OutlineInputBorder(),
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
                        border: OutlineInputBorder(),
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
                        border: OutlineInputBorder(),
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
                  onPressed: () {
                    setState(() {
                      _showAddPortForm = !_showAddPortForm;
                    });
                  },
                  icon: Icon(_showAddPortForm ? Icons.close : Icons.add, size: 18),
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
                child: Text(_isChecking ? 'Checking...' : 'Check Port'),
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

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({
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