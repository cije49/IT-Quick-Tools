import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_constants.dart';

class IpCalculatorScreen extends StatefulWidget {
  const IpCalculatorScreen({super.key});

  @override
  State<IpCalculatorScreen> createState() => _IpCalculatorScreenState();
}

class _IpCalculatorScreenState extends State<IpCalculatorScreen> {
  final TextEditingController _ipController =
      TextEditingController(text: '192.168.1.10');
  final TextEditingController _cidrController =
      TextEditingController(text: '24');

  Map<String, String>? _result;
  String? _errorMessage;

  @override
  void dispose() {
    _ipController.dispose();
    _cidrController.dispose();
    super.dispose();
  }

  void _calculate() {
    try {
      final ip = _parseIp(_ipController.text.trim());
      final cidr = int.parse(_cidrController.text.trim());

      if (cidr < 0 || cidr > 32) throw Exception('CIDR must be between 0 and 32');

      final mask = cidr == 0 ? 0 : (0xFFFFFFFF << (32 - cidr)) & 0xFFFFFFFF;
      final network = ip & mask;
      final broadcast = network | (~mask & 0xFFFFFFFF);

      final String firstHostStr, lastHostStr, usableHosts;

      if (cidr == 32) {
        firstHostStr = _intToIp(ip);
        lastHostStr = _intToIp(ip);
        usableHosts = '1 (host route)';
      } else if (cidr == 31) {
        firstHostStr = _intToIp(network);
        lastHostStr = _intToIp(broadcast);
        usableHosts = '2 (point-to-point, RFC 3021)';
      } else {
        firstHostStr = _intToIp(network + 1);
        lastHostStr = _intToIp(broadcast - 1);
        usableHosts = ((1 << (32 - cidr)) - 2).toString();
      }

      setState(() {
        _errorMessage = null;
        _result = {
          'IP Address': _intToIp(ip),
          'Subnet Mask': _intToIp(mask),
          'Network': _intToIp(network),
          'Broadcast': cidr == 32 ? 'N/A' : _intToIp(broadcast),
          'First Host': firstHostStr,
          'Last Host': lastHostStr,
          'Usable Hosts': usableHosts,
          'CIDR': '/$cidr',
        };
      });
    } catch (e) {
      setState(() {
        _result = null;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _copyAll() async {
    if (_result == null) return;
    final text = _result!.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Result copied')));
  }

  Future<void> _copyField(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
  }

  int _parseIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) throw Exception('Invalid IP format');
    int value = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        throw Exception('Each octet must be 0–255');
      }
      value = (value << 8) | octet;
    }
    return value;
  }

  String _intToIp(int v) =>
      '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IP Calculator')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInputCard(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _calculate,
                      icon: const Icon(Icons.calculate_outlined, size: 18),
                      label: const Text('Calculate'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _result != null ? _copyAll : null,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy All'),
                  ),
                ],
              ),
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
              controller: _ipController,
              decoration: InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.1.10',
                prefixIcon: Icon(Icons.router_outlined,
                    size: 18, color: AppColors.textSubtle),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cidrController,
              decoration: InputDecoration(
                labelText: 'CIDR Prefix',
                hintText: '24',
                prefixIcon: Icon(Icons.tag_rounded,
                    size: 18, color: AppColors.textSubtle),
                prefixText: '/',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultArea() {
    if (_errorMessage != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: AppColors.statusError),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_errorMessage!,
                    style: TextStyle(color: AppColors.statusError, height: 1.4)),
              ),
            ],
          ),
        ),
      );
    }

    if (_result == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.router_outlined, size: 40, color: AppColors.textSubtle),
              const SizedBox(height: 12),
              Text(
                'Enter an IP and CIDR prefix, then tap Calculate',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSubtle, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    // Highlight cards for the most-used values.
    final network = _result!['Network'] ?? '';
    final broadcast = _result!['Broadcast'] ?? '';
    final hosts = _result!['Usable Hosts'] ?? '';

    return Column(
      children: [
        // Top summary row
        Row(
          children: [
            _highlightCard(
              label: 'Network',
              value: network,
              icon: Icons.hub_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            _highlightCard(
              label: 'Hosts',
              value: hosts,
              icon: Icons.devices_outlined,
              color: AppColors.statusOpen,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Detail card with all rows
        Card(
          child: Column(
            children: [
              for (final entry in _result!.entries) ...[
                _resultRow(entry.key, entry.value),
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

  Widget _highlightCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return InkWell(
      onTap: () => _copyField(label, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSubtle,
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: SelectableText(
                      value,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy_outlined,
                      size: 13, color: AppColors.textSubtle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
