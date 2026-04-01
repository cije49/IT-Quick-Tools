import 'dart:io';

import 'package:flutter/material.dart';
import '../core/app_constants.dart';
import 'ip_calculator_screen.dart';
import 'ping_screen.dart';
import 'port_checker_screen.dart';
import 'speed_test_screen.dart';
import 'wifi_qr_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = [
      _ToolItem(
        title: 'IP Calculator',
        icon: Icons.router_rounded,
        subtitle: 'Subnet, CIDR & hosts',
        accent: const Color(0xFF6366F1), // indigo
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const IpCalculatorScreen())),
      ),
      _ToolItem(
        title: 'Port Checker',
        icon: Icons.cable_rounded,
        subtitle: 'Test TCP connectivity',
        accent: const Color(0xFF0EA5E9), // sky
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PortCheckerScreen())),
      ),
      _ToolItem(
        title: 'Ping',
        icon: Icons.network_ping_rounded,
        subtitle: 'Latency & packet loss',
        accent: const Color(0xFF10B981), // emerald
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PingScreen())),
      ),
      _ToolItem(
        title: 'WiFi QR',
        icon: Icons.wifi_rounded,
        subtitle: 'Share WiFi instantly',
        accent: const Color(0xFFF59E0B), // amber
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WifiQrScreen())),
      ),
      _ToolItem(
        title: 'Speed Test',
        icon: Icons.speed_rounded,
        subtitle: 'Ping, download & upload',
        accent: const Color(0xFFEF4444), // red
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SpeedTestScreen())),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildGrid(context, tools),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.seed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.lan_rounded, size: 20, color: AppColors.seed),
              ),
              const SizedBox(width: 12),
              const Text(
                'IT Quick Tools',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _LocalIpBadge(),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<_ToolItem> tools) {
    // 2-column grid; if odd count, last item spans full width.
    final bool hasOdd = tools.length.isOdd;
    final int pairCount = tools.length ~/ 2;

    return ListView(
      children: [
        for (int row = 0; row < pairCount; row++) ...[
          Row(
            children: [
              Expanded(child: _ToolCard(tool: tools[row * 2])),
              const SizedBox(width: 14),
              Expanded(child: _ToolCard(tool: tools[row * 2 + 1])),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (hasOdd)
          _ToolCard(tool: tools.last, fullWidth: true),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Local IP badge ────────────────────────────────────────────────────────────

class _LocalIpBadge extends StatefulWidget {
  const _LocalIpBadge();

  @override
  State<_LocalIpBadge> createState() => _LocalIpBadgeState();
}

class _LocalIpBadgeState extends State<_LocalIpBadge> {
  late final Future<String> _ipFuture = _getLocalIp();

  static Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
      return 'Unavailable';
    } catch (_) {
      return 'Unavailable';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _ipFuture,
      builder: (context, snapshot) {
        final ip = snapshot.connectionState == ConnectionState.done
            ? (snapshot.data ?? 'Unavailable')
            : '…';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8,
                  color: ip == 'Unavailable'
                      ? AppColors.statusClosed
                      : AppColors.statusOpen),
              const SizedBox(width: 8),
              Text(
                'Local IP  ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSubtle,
                ),
              ),
              Text(
                ip,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Tool model ────────────────────────────────────────────────────────────────

class _ToolItem {
  const _ToolItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
}

// ── Tool card ─────────────────────────────────────────────────────────────────

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool, this.fullWidth = false});

  final _ToolItem tool;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: fullWidth ? 88 : 148,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: tool.onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: fullWidth
                ? Row(
                    children: [
                      _iconBox(),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [_title(), const SizedBox(height: 4), _subtitle()],
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: AppColors.textSubtle),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _iconBox(),
                      const Spacer(),
                      _title(),
                      const SizedBox(height: 5),
                      _subtitle(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _iconBox() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tool.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(tool.icon, size: 24, color: tool.accent),
    );
  }

  Widget _title() => Text(
        tool.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );

  Widget _subtitle() => Text(
        tool.subtitle,
        style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.3),
      );
}
