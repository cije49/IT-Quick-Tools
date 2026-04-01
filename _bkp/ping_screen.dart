import 'dart:async';

import 'package:dart_ping/dart_ping.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/result_row.dart';

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

  // ── Ping counters tracked here so they're always in sync with received events
  int _transmitted = 0;
  int _received = 0;
  final List<double> _times = [];

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
      _transmitted = 0;
      _received = 0;
      _times.clear();
    });

    final ping = Ping(host, count: count);

    _subscription = ping.stream.listen(
      (event) {
        if (!mounted) return;

        if (event.response != null) {
          _transmitted++;
          _received++;

          final timeMs = event.response!.time?.inMilliseconds.toDouble();
          if (timeMs != null) _times.add(timeMs);

          setState(() {
            _logs.add(
              'Reply from ${event.response!.ip}: '
              'seq=${event.response!.seq} '
              'time=${event.response!.time?.inMilliseconds ?? '-'} ms',
            );
          });
        } else if (event.error != null) {
          _transmitted++;
          setState(() {
            _logs.add('Error: ${event.error}');
          });
        } else if (event.summary != null) {
          // Use our own counters (more reliable across platforms).
          _buildSummary(host);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _summary = null;
          _errorMessage = error.toString();
          _isPinging = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        // Guard: if summary wasn't set by the summary event, set it now.
        if (_isPinging) {
          _buildSummary(host);
        }
      },
      cancelOnError: false,
    );
  }

  void _buildSummary(String host) {
    final min = _times.isEmpty ? 0.0 : _times.reduce((a, b) => a < b ? a : b);
    final max = _times.isEmpty ? 0.0 : _times.reduce((a, b) => a > b ? a : b);
    final avg = _times.isEmpty
        ? 0.0
        : _times.reduce((a, b) => a + b) / _times.length;
    final loss = _transmitted == 0
        ? 0.0
        : (_transmitted - _received) / _transmitted * 100;

    setState(() {
      _summary = {
        'Host': host,
        'Packets Sent': _transmitted.toString(),
        'Packets Received': _received.toString(),
        'Packet Loss': '${loss.toStringAsFixed(1)}%',
        'Min Time': '${min.toStringAsFixed(1)} ms',
        'Avg Time': '${avg.toStringAsFixed(1)} ms',
        'Max Time': '${max.toStringAsFixed(1)} ms',
      };
      _isPinging = false;
    });
  }

  Future<void> _stopPing() async {
    await _subscription?.cancel();
    if (!mounted) return;
    setState(() {
      _isPinging = false;
      _logs.add('Ping stopped by user.');
    });
    // Build a partial summary from whatever we've collected.
    if (_transmitted > 0) {
      _buildSummary(_hostController.text.trim());
    }
  }

  Future<void> _copyResult() async {
    final summaryText = _summary == null
        ? ''
        : _summary!.entries.map((e) => '${e.key}: ${e.value}').join('\n');

    final logText = _logs.join('\n');
    final combined = [summaryText, logText]
        .where((p) => p.trim().isNotEmpty)
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

    final entries = _summary!.entries.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (int i = 0; i < entries.length; i++) ...[
              ResultRow(label: entries[i].key, value: entries[i].value),
              if (i < entries.length - 1) const Divider(height: 24),
            ],
          ],
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
      appBar: AppBar(title: const Text('Ping')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host or IP',
                hintText: 'google.com or 8.8.8.8',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _countController,
              decoration: const InputDecoration(
                labelText: 'Ping Count',
                hintText: '4',
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
              child: SingleChildScrollView(child: _buildLogBox()),
            ),
          ],
        ),
      ),
    );
  }
}
