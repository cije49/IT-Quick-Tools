import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_constants.dart';

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

  Map<String, String>? _result;
  String? _resultStatus;
  String? _errorMessage;
  bool _isChecking = false;
  bool _showAddPortForm = false;

  List<Map<String, dynamic>> _customPorts = [];

  static const List<Map<String, dynamic>> _builtInPorts = [
    {'label': 'SSH',   'port': 22},
    {'label': 'HTTP',  'port': 80},
    {'label': 'HTTPS', 'port': 443},
    {'label': 'DNS',   'port': 53},
    {'label': 'RDP',   'port': 3389},
    {'label': 'SMB',   'port': 445},
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
        AppKeys.savedCustomPorts, ports.map(jsonEncode).toList());
    if (!mounted) return;
    setState(() => _customPorts = ports);
  }

  // ── Custom port CRUD ─────────────────────────────────────────────────────────

  Future<void> _saveCustomPort() async {
    final label = _newPortLabelController.text.trim();
    final port = int.tryParse(_newPortNumberController.text.trim());
    if (label.isEmpty) { _showSnack('Label cannot be empty'); return; }
    if (port == null || port < 1 || port > 65535) {
      _showSnack('Port must be 1–65535');
      return;
    }
    final exists = _customPorts.any(
      (i) => (i['label'] ?? '').toString().toLowerCase() == label.toLowerCase()
          && i['port'] == port,
    );
    if (exists) { _showSnack('Already saved'); return; }
    await _persistCustomPorts([..._customPorts, {'label': label, 'port': port}]);
    _newPortLabelController.clear();
    _newPortNumberController.clear();
    if (!mounted) return;
    setState(() => _showAddPortForm = false);
    _showSnack('Port saved');
  }

  Future<void> _deleteCustomPort(int index) async {
    final item = _customPorts[index];
    final label = item['label']?.toString() ?? 'this port';
    final port = item['port']?.toString() ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved port?'),
        content: Text('Remove "$label${port.isEmpty ? '' : ' · $port'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    final updated = [..._customPorts]..removeAt(index);
    await _persistCustomPorts(updated);
    if (!mounted) return;
    _showSnack('Port deleted');
  }

  // ── Port check ───────────────────────────────────────────────────────────────

  Future<void> _checkPort() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    final timeout = int.tryParse(_timeoutController.text.trim());

    if (host.isEmpty) { _setError('Host cannot be empty.'); return; }
    if (port == null || port < 1 || port > 65535) { _setError('Port must be 1–65535.'); return; }
    if (timeout == null || timeout < 1 || timeout > 60) { _setError('Timeout must be 1–60 s.'); return; }

    setState(() {
      _isChecking = true;
      _result = null;
      _resultStatus = null;
      _errorMessage = null;
    });

    final sw = Stopwatch()..start();

    try {
      final socket = await Socket.connect(host, port, timeout: Duration(seconds: timeout));
      sw.stop();
      await socket.close();
      if (!mounted) return;
      setState(() {
        _resultStatus = 'OPEN';
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'OPEN',
          'Response Time': '${sw.elapsedMilliseconds} ms',
          'Timeout': '${timeout}s',
        };
      });
    } on SocketException catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _resultStatus = 'CLOSED';
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'CLOSED / UNREACHABLE',
          'Details': e.message,
          'Timeout': '${timeout}s',
        };
      });
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _resultStatus = 'ERROR';
        _result = {
          'Host': host,
          'Port': port.toString(),
          'Status': 'ERROR',
          'Details': e.toString(),
          'Timeout': '${timeout}s',
        };
      });
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  void _setError(String msg) => setState(() {
        _result = null;
        _resultStatus = null;
        _errorMessage = msg;
      });

  Future<void> _copyResult() async {
    if (_result == null) return;
    await Clipboard.setData(ClipboardData(
        text: _result!.entries.map((e) => '${e.key}: ${e.value}').join('\n')));
    if (!mounted) return;
    _showSnack('Copied');
  }

  void _setPort(int port) => _portController.text = port.toString();

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Port Checker')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInputCard(),
              const SizedBox(height: 14),
              _buildPortsSection(),
              const SizedBox(height: 16),
              _buildCheckButton(),
              const SizedBox(height: 20),
              _buildResultArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _hostController,
              decoration: InputDecoration(
                labelText: 'Host or IP',
                hintText: 'example.com or 192.168.1.1',
                prefixIcon:
                    Icon(Icons.dns_outlined, size: 18, color: AppColors.textSubtle),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _portController,
                    decoration: InputDecoration(
                      labelText: 'Port',
                      hintText: '443',
                      prefixIcon: Icon(Icons.electrical_services_outlined,
                          size: 18, color: AppColors.textSubtle),
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
          ],
        ),
      ),
    );
  }

  Widget _buildPortsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Built-in
            Text('Quick select',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSubtle)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _builtInPorts
                  .map((item) => ActionChip(
                        label: Text('${item['label']} ${item['port']}'),
                        onPressed: () => _setPort(item['port'] as int),
                      ))
                  .toList(),
            ),
            if (_customPorts.isNotEmpty || _showAddPortForm) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: AppColors.borderDefault),
              const SizedBox(height: 14),
            ],
            if (_customPorts.isNotEmpty) ...[
              Row(
                children: [
                  Text('Saved',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSubtle)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showAddPortForm = !_showAddPortForm),
                    child: Icon(
                      _showAddPortForm ? Icons.close : Icons.add,
                      size: 18,
                      color: AppColors.textSubtle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_customPorts.length, (i) {
                  final item = _customPorts[i];
                  final label = item['label']?.toString() ?? 'Port';
                  final port = item['port']?.toString() ?? '';
                  return InputChip(
                    label: Text('$label $port'),
                    onPressed: () {
                      final p = int.tryParse(port);
                      if (p != null) _setPort(p);
                    },
                    onDeleted: () => _deleteCustomPort(i),
                  );
                }),
              ),
            ],
            if (!_customPorts.isNotEmpty || _showAddPortForm)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _showAddPortForm = !_showAddPortForm),
                  icon: Icon(
                    _showAddPortForm ? Icons.close : Icons.add,
                    size: 16,
                  ),
                  label: Text(_showAddPortForm ? 'Cancel' : 'Save custom port'),
                ),
              ),
            if (_showAddPortForm) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPortLabelController,
                      decoration: const InputDecoration(
                          labelText: 'Label', hintText: 'MySQL'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _newPortNumberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Port', hintText: '3306'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: _saveCustomPort,
                    child: const Text('Save Port')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCheckButton() {
    return ElevatedButton.icon(
      onPressed: _isChecking ? null : _checkPort,
      icon: _isChecking
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
            )
          : const Icon(Icons.search_rounded, size: 20),
      label: Text(_isChecking ? 'Checking…' : 'Check Port'),
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
    );
  }

  Widget _buildResultArea() {
    if (_errorMessage != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.error_outline, color: AppColors.statusError),
            const SizedBox(width: 12),
            Expanded(child: Text(_errorMessage!,
                style: TextStyle(color: AppColors.statusError))),
          ]),
        ),
      );
    }

    if (_result == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Icon(Icons.electrical_services_outlined,
                size: 40, color: AppColors.textSubtle),
            const SizedBox(height: 12),
            Text('Fill in a host and port, then tap Check Port',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSubtle, height: 1.5)),
          ]),
        ),
      );
    }

    final status = _resultStatus ?? 'ERROR';
    final statusColor = status == 'OPEN'
        ? AppColors.statusOpen
        : status == 'CLOSED'
            ? AppColors.statusClosed
            : AppColors.statusError;

    return Column(
      children: [
        // Big status banner
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    status == 'OPEN'
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    color: statusColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status == 'OPEN' ? 'Port Open' :
                      status == 'CLOSED' ? 'Port Closed' : 'Error',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_result!['Host'] ?? ''} : ${_result!['Port'] ?? ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSubtle,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy result',
                  onPressed: _copyResult,
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Detail rows
        Card(
          child: Column(
            children: [
              for (final entry in _result!.entries
                  .where((e) => e.key != 'Host' && e.key != 'Port' && e.key != 'Status')) ...[
                _detailRow(entry.key, entry.value),
                if (entry.key != _result!.keys.last)
                  Divider(height: 1, indent: 16, endIndent: 16,
                      color: AppColors.borderDefault),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSubtle)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
