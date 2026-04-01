import 'dart:async';

import 'package:dart_ping/dart_ping.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PingScreen extends StatefulWidget {
  const PingScreen({super.key});

  @override
  State<PingScreen> createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen> {
  final TextEditingController _hostController =
      TextEditingController(text: 'google.com');
  final TextEditingController _countController =
      TextEditingController(text: '4');

  final List<String> _logs = [];
  StreamSubscription<PingData>? _subscription;

  bool _isPinging = false;
  Map<String, String>? _summary;
  String? _errorMessage;

  @override
  void dispose() {
    _subscription?.cancel();
    _hostController.dispose();
    _countController.dispose();
    super.dispose();
  }

  Future<void> _startPing() async {
    final host = _hostController.text.trim();
    final count = int.tryParse(_countController.text.trim());

    if (host.isEmpty) {
      setState(() {
        _summary = null;
        _errorMessage = 'Host cannot be empty.';
      });
      return;
    }

    if (count == null || count < 1 || count > 20) {
      setState(() {
        _summary = null;
        _errorMessage = 'Count must be between 1 and 20.';
      });
      return;
    }

    await _subscription?.cancel();

    setState(() {
      _logs.clear();
      _summary = null;
      _errorMessage = null;
      _isPinging = true;
    });

    int transmitted = 0;
    int received = 0;
    final List<double> times = [];

    final ping = Ping(
      host,
      count: count,
    );

    _subscription = ping.stream.listen(
      (event) {
        if (!mounted) return;

        if (event.response != null) {
          transmitted++;
          received++;

          final time = event.response!.time?.inMilliseconds.toDouble();
          if (time != null) {
            times.add(time);
          }

          setState(() {
            _logs.add(
              'Reply from ${event.response!.ip}: '
              'seq=${event.response!.seq} '
              'time=${event.response!.time?.inMilliseconds ?? '-'} ms',
            );
          });
        } else if (event.error != null) {
          transmitted++;
          setState(() {
            _logs.add('Error: ${event.error}');
          });
        } else if (event.summary != null) {
          final min = times.isEmpty
              ? 0
              : times.reduce((a, b) => a < b ? a : b);
          final max = times.isEmpty
              ? 0
              : times.reduce((a, b) => a > b ? a : b);
          final avg = times.isEmpty
              ? 0
              : times.reduce((a, b) => a + b) / times.length;
          final loss = transmitted == 0
              ? 0
              : ((transmitted - received) / transmitted * 100);

          setState(() {
            _summary = {
              'Host': host,
              'Packets Sent': transmitted.toString(),
              'Packets Received': received.toString(),
              'Packet Loss': '${loss.toStringAsFixed(1)}%',
              'Min Time': '${min.toStringAsFixed(1)} ms',
              'Avg Time': '${avg.toStringAsFixed(1)} ms',
              'Max Time': '${max.toStringAsFixed(1)} ms',
            };
            _isPinging = false;
          });
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _summary = null;
          _errorMessage = error.toString();
          _isPinging = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isPinging = false;
        });
      },
      cancelOnError: false,
    );
  }

  Future<void> _stopPing() async {
    await _subscription?.cancel();
    setState(() {
      _isPinging = false;
      _logs.add('Ping stopped by user.');
    });
  }

  Future<void> _copyResult() async {
    final summaryText = _summary == null
        ? ''
        : _summary!.entries.map((e) => '${e.key}: ${e.value}').join('\n');

    final logText = _logs.join('\n');

    final combined = [summaryText, logText]
        .where((part) => part.trim().isNotEmpty)
        .join('\n\n');

    if (combined.trim().isEmpty) return;

    await Clipboard.setData(ClipboardData(text: combined));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ping result copied to clipboard')),
    );
  }

  Widget _buildSummaryContent() {
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

    if (_summary == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Enter host and count, then press Start Ping.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: _summary!.entries.map((entry) {
            final isLast = entry.key == _summary!.entries.last.key;

            return Column(
              children: [
                _ResultRow(label: entry.key, value: entry.value),
                if (!isLast) const Divider(height: 24),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLogBox() {
    final text = _logs.isEmpty ? 'No ping output yet.' : _logs.join('\n');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ping'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host or IP',
                hintText: 'google.com or 8.8.8.8',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _countController,
              decoration: const InputDecoration(
                labelText: 'Ping Count',
                hintText: '4',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isPinging ? null : _startPing,
                    child: const Text('Start Ping'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isPinging ? _stopPing : _copyResult,
                    child: Text(_isPinging ? 'Stop Ping' : 'Copy Result'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSummaryContent(),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: _buildLogBox(),
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