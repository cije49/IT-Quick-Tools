import 'dart:io';

import 'package:flutter/material.dart';

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> {
  bool _isTesting = false;

  double _downloadMbps = 0;
  double _pingMs = 0;

  String _status = 'Idle';
  String _details = 'Run a quick network check';

  Future<void> _startTest() async {
    setState(() {
      _isTesting = true;
      _downloadMbps = 0;
      _pingMs = 0;
      _status = 'Starting';
      _details = 'Preparing speed test...';
    });

    try {
      await _testPing();
      await _testDownload();

      setState(() {
        _status = 'Completed';
        _details = 'Speed test finished successfully';
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error';
        _details = e.toString();
        _isTesting = false;
      });
    }
  }

  Future<void> _testPing() async {
    const host = '8.8.8.8';
    const port = 53;

    int totalMs = 0;
    int successCount = 0;

    setState(() {
      _status = 'Ping';
      _details = 'Measuring latency...';
    });

    for (int i = 0; i < 3; i++) {
      try {
        final stopwatch = Stopwatch()..start();

        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 3),
        );

        stopwatch.stop();
        await socket.close();

        totalMs += stopwatch.elapsedMilliseconds;
        successCount++;
      } catch (_) {}
    }

    if (successCount > 0) {
      final avg = totalMs / successCount;

      setState(() {
        _pingMs = avg;
      });
    } else {
      setState(() {
        _pingMs = 0;
        _status = 'Ping failed';
        _details = 'Could not reach test server';
      });
    }
  }

  Future<void> _testDownload() async {
    final url = Uri.parse('http://ipv4.download.thinkbroadband.com/100MB.zip');

    final client = HttpClient();
    client.autoUncompress = false;

    final request = await client.getUrl(url);
    final response = await request.close();

    int totalBytes = 0;
    final stopwatch = Stopwatch()..start();

    setState(() {
      _status = 'Download';
      _details = 'Downloading test data...';
    });

    await for (final chunk in response) {
      totalBytes += chunk.length;

      final seconds = stopwatch.elapsedMilliseconds / 1000;

      if (seconds > 0) {
        final bits = totalBytes * 8;
        final mbps = bits / seconds / 1000000;

        setState(() {
          _downloadMbps = mbps;
          _details = 'Measuring download speed...';
        });
      }

      if (stopwatch.elapsedMilliseconds > 6000) {
        break;
      }
    }

    stopwatch.stop();
    client.close();
  }

  void _stopTest() {
    setState(() {
      _isTesting = false;
      _status = 'Stopped';
      _details = 'Speed test stopped by user';
    });
  }

  Widget _buildTopCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0F172A),
                border: Border.all(
                  color: const Color(0xFF334155),
                ),
              ),
              child: Icon(
                _isTesting ? Icons.speed : Icons.network_check_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _status,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _details,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(icon, size: 26, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              unit,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            label: 'Ping',
            value: _pingMs == 0 ? '--' : _pingMs.toStringAsFixed(0),
            unit: 'ms',
            icon: Icons.network_ping_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            label: 'Download',
            value: _downloadMbps == 0 ? '--' : _downloadMbps.toStringAsFixed(2),
            unit: 'Mbps',
            icon: Icons.download_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'This is a simple speed test. Results can vary depending on Wi-Fi quality, device performance, and the test server.',
          style: TextStyle(
            color: Colors.white70,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speed Test'),
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
              _buildTopCard(),
              const SizedBox(height: 16),
              _buildResultsGrid(),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isTesting ? _stopTest : _startTest,
                icon: Icon(_isTesting ? Icons.stop_circle_outlined : Icons.play_arrow_outlined),
                label: Text(_isTesting ? 'Stop Test' : 'Start Test'),
              ),
              const SizedBox(height: 16),
              _buildInfoCard(),
            ],
          ),
        ),
      ),
    );
  }
}