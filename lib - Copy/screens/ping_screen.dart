import 'dart:async';
import 'dart:math' as math;

import 'package:dart_ping/dart_ping.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_constants.dart';

class PingScreen extends StatefulWidget {
  const PingScreen({super.key});

  @override
  State<PingScreen> createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _hostController =
      TextEditingController(text: 'google.com');
  final TextEditingController _countController =
      TextEditingController(text: '8');

  final List<String> _logs = [];
  // Raw RTT per reply (ms), used for bar chart.
  final List<double> _rtts = [];

  StreamSubscription<PingData>? _subscription;

  bool _isPinging = false;
  Map<String, String>? _summary;
  String? _errorMessage;

  int _transmitted = 0;
  int _received = 0;
  final List<double> _times = [];

  // Pulse animation for the "live" indicator.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _subscription?.cancel();
    _pulseController.dispose();
    _hostController.dispose();
    _countController.dispose();
    super.dispose();
  }

  Future<void> _startPing() async {
    final host = _hostController.text.trim();
    final count = int.tryParse(_countController.text.trim());

    if (host.isEmpty) {
      setState(() { _summary = null; _errorMessage = 'Host cannot be empty.'; });
      return;
    }
    if (count == null || count < 1 || count > 20) {
      setState(() { _summary = null; _errorMessage = 'Count must be between 1 and 20.'; });
      return;
    }

    await _subscription?.cancel();

    setState(() {
      _logs.clear();
      _rtts.clear();
      _summary = null;
      _errorMessage = null;
      _isPinging = true;
      _transmitted = 0;
      _received = 0;
      _times.clear();
    });
    _pulseController.repeat(reverse: true);

    final ping = Ping(host, count: count);

    _subscription = ping.stream.listen(
      (event) {
        if (!mounted) return;

        if (event.response != null) {
          _transmitted++;
          _received++;
          final timeMs = event.response!.time?.inMilliseconds.toDouble();
          if (timeMs != null) {
            _times.add(timeMs);
            setState(() => _rtts.add(timeMs));
          }
          setState(() {
            _logs.add(
              'Reply from ${event.response!.ip}  '
              'seq=${event.response!.seq}  '
              '${event.response!.time?.inMilliseconds ?? '-'} ms',
            );
          });
        } else if (event.error != null) {
          _transmitted++;
          setState(() => _logs.add('Timeout / error: ${event.error}'));
        } else if (event.summary != null) {
          _buildSummary(host);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() { _summary = null; _errorMessage = error.toString(); _isPinging = false; });
        _pulseController.stop();
      },
      onDone: () {
        if (!mounted) return;
        if (_isPinging) _buildSummary(host);
        _pulseController.stop();
      },
      cancelOnError: false,
    );
  }

  void _buildSummary(String host) {
    final min = _times.isEmpty ? 0.0 : _times.reduce((a, b) => a < b ? a : b);
    final max = _times.isEmpty ? 0.0 : _times.reduce((a, b) => a > b ? a : b);
    final avg = _times.isEmpty ? 0.0 : _times.reduce((a, b) => a + b) / _times.length;
    final loss = _transmitted == 0
        ? 0.0
        : (_transmitted - _received) / _transmitted * 100;

    setState(() {
      _summary = {
        'Host': host,
        'Sent': _transmitted.toString(),
        'Received': _received.toString(),
        'Loss': '${loss.toStringAsFixed(1)}%',
        'Min': '${min.toStringAsFixed(1)} ms',
        'Avg': '${avg.toStringAsFixed(1)} ms',
        'Max': '${max.toStringAsFixed(1)} ms',
      };
      _isPinging = false;
    });
  }

  Future<void> _stopPing() async {
    await _subscription?.cancel();
    _pulseController.stop();
    if (!mounted) return;
    setState(() {
      _isPinging = false;
      _logs.add('— Stopped by user —');
    });
    if (_transmitted > 0) _buildSummary(_hostController.text.trim());
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
        const SnackBar(content: Text('Ping result copied')));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ping')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInputCard(),
              const SizedBox(height: 14),
              _buildActionRow(),
              const SizedBox(height: 16),
              if (_errorMessage != null) _buildErrorCard(),
              if (_summary != null) ...[
                _buildSummaryCards(),
                const SizedBox(height: 14),
              ],
              if (_rtts.isNotEmpty) ...[
                _buildRttChart(),
                const SizedBox(height: 14),
              ],
              if (_logs.isNotEmpty)
                Expanded(child: _buildLogCard()),
              if (_logs.isEmpty && _summary == null && _errorMessage == null)
                _buildPlaceholder(),
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
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: 'Host or IP',
                  hintText: 'google.com',
                  prefixIcon: Icon(Icons.dns_outlined,
                      size: 18, color: AppColors.textSubtle),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _countController,
                decoration: const InputDecoration(
                  labelText: 'Count',
                  hintText: '8',
                ),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isPinging ? null : _startPing,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Start Ping'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isPinging
                ? _stopPing
                : (_logs.isNotEmpty ? _copyResult : null),
            icon: Icon(
              _isPinging ? Icons.stop_rounded : Icons.copy_outlined,
              size: 18,
            ),
            label: Text(_isPinging ? 'Stop' : 'Copy Result'),
            style: _isPinging
                ? OutlinedButton.styleFrom(
                    foregroundColor: AppColors.statusClosed,
                    side: BorderSide(color: AppColors.statusClosed),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.statusError),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(color: AppColors.statusError, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final s = _summary!;
    final lossVal = double.tryParse(s['Loss']?.replaceAll('%', '') ?? '0') ?? 0;
    final lossColor = lossVal == 0
        ? AppColors.statusOpen
        : lossVal < 10
            ? AppColors.statusError
            : AppColors.statusClosed;

    return Column(
      children: [
        // Live indicator while pinging
        if (_isPinging)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildLiveIndicator(),
          ),
        // Stat chips
        Row(
          children: [
            _statChip(
                label: 'Sent', value: s['Sent'] ?? '--',
                icon: Icons.upload_outlined),
            const SizedBox(width: 10),
            _statChip(
                label: 'Received', value: s['Received'] ?? '--',
                icon: Icons.download_outlined),
            const SizedBox(width: 10),
            _statChip(
                label: 'Loss', value: s['Loss'] ?? '--',
                icon: Icons.warning_amber_rounded,
                valueColor: lossColor),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statChip(
                label: 'Min', value: s['Min'] ?? '--',
                icon: Icons.arrow_downward_rounded),
            const SizedBox(width: 10),
            _statChip(
                label: 'Avg', value: s['Avg'] ?? '--',
                icon: Icons.horizontal_rule_rounded),
            const SizedBox(width: 10),
            _statChip(
                label: 'Max', value: s['Max'] ?? '--',
                icon: Icons.arrow_upward_rounded),
          ],
        ),
      ],
    );
  }

  Widget _statChip({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: AppColors.textSubtle),
            const SizedBox(height: 6),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: AppColors.textSubtle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveIndicator() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.statusOpen
                    .withValues(alpha: 0.4 + 0.6 * _pulseController.value),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Pinging ${_hostController.text.trim()}…',
              style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRttChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'RTT per reply',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const Spacer(),
                if (_isPinging)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.statusOpen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Live',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.statusOpen,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              child: CustomPaint(
                painter: _RttBarPainter(
                  rtts: _rtts,
                  color: Theme.of(context).colorScheme.primary,
                ),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('1', style: TextStyle(fontSize: 10, color: AppColors.textSubtle)),
                Text(
                  '${_rtts.length} replies',
                  style: TextStyle(fontSize: 10, color: AppColors.textSubtle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              'Output',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SelectableText(
                _logs.join('\n'),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  fontFamily: 'monospace',
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.network_ping_outlined, size: 48, color: AppColors.textSubtle),
            const SizedBox(height: 12),
            Text(
              'Enter a host and press Start Ping',
              style: TextStyle(color: AppColors.textSubtle, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── RTT bar chart painter ─────────────────────────────────────────────────────

class _RttBarPainter extends CustomPainter {
  const _RttBarPainter({required this.rtts, required this.color});
  final List<double> rtts;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (rtts.isEmpty) return;
    final maxVal = rtts.reduce(math.max);
    if (maxVal == 0) return;

    final barW = size.width / rtts.length;
    final gap = barW * 0.25;

    for (int i = 0; i < rtts.length; i++) {
      final barH = (rtts[i] / maxVal) * size.height;
      final left = i * barW + gap / 2;
      final right = (i + 1) * barW - gap / 2;
      final top = size.height - barH;

      canvas.drawRRect(
        RRect.fromLTRBR(left, top, right, size.height, const Radius.circular(3)),
        Paint()..color = color.withValues(alpha: 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_RttBarPainter old) => old.rtts != rtts;
}
