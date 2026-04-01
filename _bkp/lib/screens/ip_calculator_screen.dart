import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

      if (cidr < 0 || cidr > 32) {
        throw Exception('CIDR must be between 0 and 32');
      }

      final mask = cidr == 0 ? 0 : (0xFFFFFFFF << (32 - cidr)) & 0xFFFFFFFF;
      final network = ip & mask;
      final broadcast = network | (~mask & 0xFFFFFFFF);

      final firstHost = cidr >= 31 ? network : network + 1;
      final lastHost = cidr >= 31 ? broadcast : broadcast - 1;
      final hostCount = cidr >= 31 ? 0 : (1 << (32 - cidr)) - 2;

      setState(() {
        _errorMessage = null;
        _result = {
          'IP Address': _intToIp(ip),
          'CIDR': '/$cidr',
          'Subnet Mask': _intToIp(mask),
          'Network Address': _intToIp(network),
          'Broadcast Address': _intToIp(broadcast),
          'First Host': _intToIp(firstHost),
          'Last Host': _intToIp(lastHost),
          'Usable Hosts': hostCount.toString(),
        };
      });
    } catch (e) {
      setState(() {
        _result = null;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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

  int _parseIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      throw Exception('Invalid IP format');
    }

    int value = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        throw Exception('Each IP octet must be between 0 and 255');
      }
      value = (value << 8) | octet;
    }
    return value;
  }

  String _intToIp(int value) {
    return '${(value >> 24) & 0xFF}.'
        '${(value >> 16) & 0xFF}.'
        '${(value >> 8) & 0xFF}.'
        '${value & 0xFF}';
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
            'Enter IP and CIDR, then press Calculate.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: _result!.entries.map((entry) {
            final isLast = entry.key == _result!.entries.last.key;

            return Column(
              children: [
                _ResultRow(
                  label: entry.key,
                  value: entry.value,
                ),
                if (!isLast) const Divider(height: 24),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IP Calculator'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.1.10',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cidrController,
              decoration: const InputDecoration(
                labelText: 'CIDR',
                hintText: '24',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _calculate,
                    child: const Text('Calculate'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _copyResult,
                    child: const Text('Copy Result'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: _buildResultContent(),
              ),
            ),
          ],
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