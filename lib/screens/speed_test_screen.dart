import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../core/app_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { idle, ping, download, upload, done, error, stopped }

extension _PhaseLabel on _Phase {
  String get label {
    switch (this) {
      case _Phase.idle:     return 'Idle';
      case _Phase.ping:     return 'Ping';
      case _Phase.download: return 'Download';
      case _Phase.upload:   return 'Upload';
      case _Phase.done:     return 'Completed';
      case _Phase.error:    return 'Error';
      case _Phase.stopped:  return 'Stopped';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.idle;
  bool _cancelRequested = false;

  double _pingMs = 0;
  double _downloadMbps = 0;
  double _uploadMbps = 0;

  // Per-second speed samples for sparklines.
  final List<double> _downloadSamples = [];
  final List<double> _uploadSamples = [];

  String _details = 'Tap Start Test to begin';
  String? _errorMessage;

  // ── Animation ──────────────────────────────────────────────────────────────
  late final AnimationController _ringController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool get _isTesting =>
      _phase == _Phase.ping ||
      _phase == _Phase.download ||
      _phase == _Phase.upload;

  void _update(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // ── Test orchestration ─────────────────────────────────────────────────────

  Future<void> _startTest() async {
    _update(() {
      _phase = _Phase.ping;
      _cancelRequested = false;
      _pingMs = 0;
      _downloadMbps = 0;
      _uploadMbps = 0;
      _downloadSamples.clear();
      _uploadSamples.clear();
      _details = 'Measuring latency...';
      _errorMessage = null;
    });

    try {
      await _testPing();
      if (_cancelRequested) return;

      _update(() {
        _phase = _Phase.download;
        _details = 'Downloading test data...';
      });
      await _testDownload();
      if (_cancelRequested) return;

      _update(() {
        _phase = _Phase.upload;
        _details = 'Uploading test data...';
      });
      await _testUpload();
      if (_cancelRequested) return;

      _update(() {
        _phase = _Phase.done;
        _details = 'All tests completed';
      });
    } catch (e) {
      _update(() {
        _phase = _Phase.error;
        _details = 'Test failed';
        _errorMessage = e.toString();
      });
    }
  }

  void _stopTest() {
    _cancelRequested = true;
    _update(() {
      _phase = _Phase.stopped;
      _details = 'Test stopped by user';
    });
  }

  // ── Ping ───────────────────────────────────────────────────────────────────

  Future<void> _testPing() async {
    const host = '8.8.8.8';
    const port = 53;
    const attempts = 4;

    int totalMs = 0;
    int successCount = 0;

    for (int i = 0; i < attempts; i++) {
      if (_cancelRequested) return;
      try {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect(
          host, port,
          timeout: const Duration(seconds: 3),
        );
        sw.stop();
        await socket.close();
        totalMs += sw.elapsedMilliseconds;
        successCount++;
        _update(() => _pingMs = totalMs / successCount);
      } catch (_) {}
    }

    if (successCount == 0 && !_cancelRequested) {
      _update(() {
        _details = 'Could not reach test server - ping failed';
      });
    }
  }

  // ── Download ───────────────────────────────────────────────────────────────

  Future<void> _testDownload() async {
    final url = Uri.parse('http://ipv4.download.thinkbroadband.com/100MB.zip');
    final client = HttpClient()..autoUncompress = false;

    try {
      final request = await client.getUrl(url);
      final response = await request.close();

      int totalBytes = 0;
      final sw = Stopwatch()..start();
      int lastSampleMs = 0;
      int bytesAtLastSample = 0;

      await for (final chunk in response) {
        if (_cancelRequested) break;

        totalBytes += chunk.length;
        final elapsedMs = sw.elapsedMilliseconds;
        final seconds = elapsedMs / 1000;

        if (seconds > 0) {
          final mbps = (totalBytes * 8) / seconds / 1000000;
          _update(() => _downloadMbps = mbps);
        }

        // Per-second sample for sparkline.
        if (elapsedMs - lastSampleMs >= 1000) {
          final intervalBytes = totalBytes - bytesAtLastSample;
          final intervalSec = (elapsedMs - lastSampleMs) / 1000;
          if (intervalSec > 0) {
            final sampleMbps = (intervalBytes * 8) / intervalSec / 1000000;
            _update(() => _downloadSamples.add(sampleMbps));
          }
          lastSampleMs = elapsedMs;
          bytesAtLastSample = totalBytes;
        }

        if (elapsedMs > 10000) break;
      }
      sw.stop();
    } finally {
      client.close(force: true);
    }
  }

  // ── Upload ─────────────────────────────────────────────────────────────────

  Future<void> _testUpload() async {
    const uploadDurationMs = 8000;
    const chunkSize = 32 * 1024; // 32 KB

    final rng = math.Random();
    final payload = Uint8List.fromList(
      List.generate(chunkSize, (_) => rng.nextInt(256)),
    );

    Socket? socket;

    try {
      socket = await Socket.connect(
        'tcpbin.com', 4242,
        timeout: const Duration(seconds: 4),
      );

      int totalBytes = 0;
      final sw = Stopwatch()..start();
      int lastSampleMs = 0;
      int bytesAtLastSample = 0;

      socket.listen((_) {}, onError: (_) {}, cancelOnError: false);

      while (sw.elapsedMilliseconds < uploadDurationMs && !_cancelRequested) {
        socket.add(payload);
        await socket.flush();
        totalBytes += chunkSize;

        final elapsedMs = sw.elapsedMilliseconds;
        final seconds = elapsedMs / 1000;
        if (seconds > 0) {
          final mbps = (totalBytes * 8) / seconds / 1000000;
          _update(() => _uploadMbps = mbps);
        }

        if (elapsedMs - lastSampleMs >= 1000) {
          final intervalBytes = totalBytes - bytesAtLastSample;
          final intervalSec = (elapsedMs - lastSampleMs) / 1000;
          if (intervalSec > 0) {
            final sampleMbps = (intervalBytes * 8) / intervalSec / 1000000;
            _update(() => _uploadSamples.add(sampleMbps));
          }
          lastSampleMs = elapsedMs;
          bytesAtLastSample = totalBytes;
        }
      }
      sw.stop();
    } catch (_) {
      // Upload failed silently - leave _uploadMbps at 0.
    } finally {
      await socket?.close();
    }
  }

  // ── Quality rating ─────────────────────────────────────────────────────────

  _Quality _downloadQuality() {
    if (_downloadMbps == 0) return _Quality.unknown;
    if (_downloadMbps >= 100) return _Quality.excellent;
    if (_downloadMbps >= 25)  return _Quality.good;
    if (_downloadMbps >= 5)   return _Quality.fair;
    return _Quality.poor;
  }

  _Quality _pingQuality() {
    if (_pingMs == 0)   return _Quality.unknown;
    if (_pingMs < 20)   return _Quality.excellent;
    if (_pingMs < 60)   return _Quality.good;
    if (_pingMs < 150)  return _Quality.fair;
    return _Quality.poor;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speed Test')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPhaseIndicator(),
              const SizedBox(height: 20),
              _buildGaugeCard(),
              const SizedBox(height: 16),
              _buildMetricsRow(),
              const SizedBox(height: 16),
              _buildStartStopButton(),
              if (_phase == _Phase.done || _phase == _Phase.stopped) ...[
                const SizedBox(height: 20),
                if (_downloadSamples.isNotEmpty)
                  _buildSparklineCard(
                    title: 'Download speed over time',
                    samples: _downloadSamples,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                if (_uploadSamples.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildSparklineCard(
                    title: 'Upload speed over time',
                    samples: _uploadSamples,
                    color: const Color(0xFF34D399),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              _buildInfoCard(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Phase stepper ──────────────────────────────────────────────────────────

  Widget _buildPhaseIndicator() {
    const phases = [_Phase.ping, _Phase.download, _Phase.upload];
    const labels = ['Ping', 'Download', 'Upload'];

    return Row(
      children: List.generate(phases.length * 2 - 1, (i) {
        if (i.isOdd) {
          final leftPhase = phases[i ~/ 2];
          final passed = _phaseIndex(_phase) > _phaseIndex(leftPhase);
          return Expanded(
            child: Container(
              height: 2,
              color: passed
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.borderInput,
            ),
          );
        }

        final idx = i ~/ 2;
        final ph = phases[idx];
        final currentIdx = _phaseIndex(_phase);
        final phIdx = _phaseIndex(ph);

        final isDone   = currentIdx > phIdx;
        final isActive = currentIdx == phIdx && _isTesting;
        final isPending = currentIdx < phIdx;

        Color dotColor;
        Widget dotChild;
        if (isDone) {
          dotColor = Theme.of(context).colorScheme.primary;
          dotChild = const Icon(Icons.check, size: 14, color: Colors.white);
        } else if (isActive) {
          dotColor = Theme.of(context).colorScheme.primary;
          dotChild = const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          );
        } else {
          dotColor = AppColors.chipBg;
          dotChild = Text(
            '${idx + 1}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isPending ? AppColors.textSubtle : Colors.white70,
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
              child: Center(child: dotChild),
            ),
            const SizedBox(height: 6),
            Text(
              labels[idx],
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: (isDone || isActive)
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.textSubtle,
              ),
            ),
          ],
        );
      }),
    );
  }

  int _phaseIndex(_Phase p) {
    switch (p) {
      case _Phase.idle:
      case _Phase.stopped:
      case _Phase.error:    return 0;
      case _Phase.ping:     return 1;
      case _Phase.download: return 2;
      case _Phase.upload:   return 3;
      case _Phase.done:     return 4;
    }
  }

  // ── Animated gauge card ────────────────────────────────────────────────────

  Widget _buildGaugeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
        child: Column(
          children: [
            SizedBox(
              width: 130,
              height: 130,
              child: _isTesting
                  ? AnimatedBuilder(
                      animation: _ringController,
                      builder: (_, __) => CustomPaint(
                        painter: _SpinningRingPainter(
                          progress: _ringController.value,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        child: _gaugeCenter(),
                      ),
                    )
                  : CustomPaint(
                      painter: _StaticRingPainter(
                        filled: _phase == _Phase.done,
                        color: Theme.of(context).colorScheme.primary,
                        borderColor: AppColors.borderInput,
                      ),
                      child: _gaugeCenter(),
                    ),
            ),
            const SizedBox(height: 20),
            Text(
              _phase.label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? _details,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _phase == _Phase.error
                    ? AppColors.statusError
                    : AppColors.textMuted,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gaugeCenter() {
    IconData icon;
    switch (_phase) {
      case _Phase.ping:
        icon = Icons.network_ping_outlined;
      case _Phase.download:
        icon = Icons.download_outlined;
      case _Phase.upload:
        icon = Icons.upload_outlined;
      case _Phase.done:
        icon = Icons.check_circle_outline;
      case _Phase.error:
        icon = Icons.error_outline;
      case _Phase.stopped:
        icon = Icons.stop_circle_outlined;
      default:
        icon = Icons.speed_outlined;
    }

    return Center(
      child: Icon(
        icon,
        size: 44,
        color: _phase == _Phase.error
            ? AppColors.statusError
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  // ── Metric cards row ───────────────────────────────────────────────────────

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            label: 'Ping',
            value: _pingMs == 0 ? '--' : _pingMs.toStringAsFixed(0),
            unit: 'ms',
            icon: Icons.network_ping_outlined,
            quality: _pingQuality(),
            isActive: _phase == _Phase.ping,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricCard(
            label: 'Download',
            value: _downloadMbps == 0
                ? '--'
                : _downloadMbps.toStringAsFixed(1),
            unit: 'Mbps',
            icon: Icons.download_outlined,
            quality: _downloadQuality(),
            isActive: _phase == _Phase.download,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricCard(
            label: 'Upload',
            value: _uploadMbps == 0 ? '--' : _uploadMbps.toStringAsFixed(1),
            unit: 'Mbps',
            icon: Icons.upload_outlined,
            quality: _Quality.unknown,
            isActive: _phase == _Phase.upload,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required _Quality quality,
    required bool isActive,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final iconColor = isActive ? primary : AppColors.textSubtle;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isActive ? primary : AppColors.borderDefault,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: TextStyle(color: AppColors.textSubtle, fontSize: 11),
          ),
          if (quality != _Quality.unknown && value != '--') ...[
            const SizedBox(height: 8),
            _QualityBadge(quality: quality),
          ],
        ],
      ),
    );
  }

  // ── Start / stop button ────────────────────────────────────────────────────

  Widget _buildStartStopButton() {
    return ElevatedButton.icon(
      onPressed: _isTesting ? _stopTest : _startTest,
      icon: Icon(
        _isTesting ? Icons.stop_circle_outlined : Icons.play_arrow_rounded,
        size: 22,
      ),
      label: Text(
        _isTesting ? 'Stop Test' : 'Start Test',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        backgroundColor: _isTesting
            ? AppColors.statusClosed.withValues(alpha: 0.15)
            : null,
        foregroundColor: _isTesting ? AppColors.statusClosed : null,
      ),
    );
  }

  // ── Sparkline ──────────────────────────────────────────────────────────────

  Widget _buildSparklineCard({
    required String title,
    required List<double> samples,
    required Color color,
  }) {
    if (samples.isEmpty) return const SizedBox.shrink();

    final minVal = samples.reduce(math.min);
    final maxVal = samples.reduce(math.max);
    final avgVal = samples.reduce((a, b) => a + b) / samples.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: CustomPaint(
                painter: _SparklinePainter(samples: samples, color: color),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'min ${minVal.toStringAsFixed(1)} Mbps',
                  style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
                ),
                Text(
                  'avg ${avgVal.toStringAsFixed(1)} Mbps',
                  style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
                ),
                Text(
                  'max ${maxVal.toStringAsFixed(1)} Mbps',
                  style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Info card ──────────────────────────────────────────────────────────────

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Results depend on Wi-Fi signal, server distance, and device '
          'performance. Upload uses tcpbin.com:4242 (TCP discard). '
          'Run multiple tests for a reliable average.',
          style: TextStyle(
            color: AppColors.textMuted,
            height: 1.5,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quality enum + badge
// ─────────────────────────────────────────────────────────────────────────────

enum _Quality { excellent, good, fair, poor, unknown }

extension _QualityProps on _Quality {
  String get label {
    switch (this) {
      case _Quality.excellent: return 'Excellent';
      case _Quality.good:      return 'Good';
      case _Quality.fair:      return 'Fair';
      case _Quality.poor:      return 'Poor';
      case _Quality.unknown:   return '';
    }
  }

  Color get color {
    switch (this) {
      case _Quality.excellent: return const Color(0xFF22C55E);
      case _Quality.good:      return const Color(0xFF3B82F6);
      case _Quality.fair:      return const Color(0xFFF59E0B);
      case _Quality.poor:      return const Color(0xFFEF4444);
      case _Quality.unknown:   return Colors.transparent;
    }
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.quality});
  final _Quality quality;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: quality.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        quality.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: quality.color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painters
// ─────────────────────────────────────────────────────────────────────────────

class _SpinningRingPainter extends CustomPainter {
  const _SpinningRingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (math.min(size.width, size.height) / 2) - 6;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    canvas.drawArc(
      rect, 0, math.pi * 2, false,
      Paint()
        ..color = AppColors.borderInput
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    final startAngle = progress * math.pi * 2 - math.pi / 2;
    const sweepAngle = math.pi * 1.33;
    canvas.drawArc(
      rect, startAngle, sweepAngle, false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SpinningRingPainter old) => old.progress != progress;
}

class _StaticRingPainter extends CustomPainter {
  const _StaticRingPainter({
    required this.filled,
    required this.color,
    required this.borderColor,
  });
  final bool filled;
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (math.min(size.width, size.height) / 2) - 6;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    canvas.drawArc(
      rect, 0, math.pi * 2, false,
      Paint()
        ..color = filled ? color : borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_StaticRingPainter old) =>
      old.filled != filled || old.color != color;
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.samples, required this.color});
  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final maxVal = samples.reduce(math.max);
    if (maxVal == 0) return;

    final barWidth = size.width / samples.length;
    final gap = barWidth * 0.2;

    for (int i = 0; i < samples.length; i++) {
      final barH = (samples[i] / maxVal) * size.height;
      final left  = i * barWidth + gap / 2;
      final right = (i + 1) * barWidth - gap / 2;
      final top   = size.height - barH;

      canvas.drawRRect(
        RRect.fromLTRBR(left, top, right, size.height, const Radius.circular(3)),
        Paint()..color = color.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.samples != samples;
}
