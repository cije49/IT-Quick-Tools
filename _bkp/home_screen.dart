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
        icon: Icons.router_outlined,
        subtitle: 'Subnet, CIDR, hosts',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IpCalculatorScreen()),
        ),
      ),
      _ToolItem(
        title: 'Port Checker',
        icon: Icons.settings_ethernet_outlined,
        subtitle: 'Test TCP ports',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PortCheckerScreen()),
        ),
      ),
      _ToolItem(
        title: 'Ping',
        icon: Icons.network_ping_outlined,
        subtitle: 'Latency and packet loss',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PingScreen()),
        ),
      ),
      _ToolItem(
        title: 'WiFi QR',
        icon: Icons.wifi_outlined,
        subtitle: 'Share WiFi quickly',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WifiQrScreen()),
        ),
      ),
      _ToolItem(
        title: 'Speed Test',
        icon: Icons.speed_outlined,
        subtitle: 'Ping and download',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SpeedTestScreen()),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'IT Quick Tools',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LocalIpLine(),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                itemCount: tools.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.02,
                ),
                itemBuilder: (context, index) => _ToolCard(tool: tools[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Local IP widget ───────────────────────────────────────────────────────────

/// Displays the device's first non-loopback IPv4 address.
///
/// The Future is created once inside [State.initState] so repeated widget
/// rebuilds don't spawn a new network lookup each time.
class _LocalIpLine extends StatefulWidget {
  const _LocalIpLine();

  @override
  State<_LocalIpLine> createState() => _LocalIpLineState();
}

class _LocalIpLineState extends State<_LocalIpLine> {
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
        final value = snapshot.connectionState == ConnectionState.done
            ? (snapshot.data ?? 'Unavailable')
            : 'Loading…';

        return Row(
          children: [
            Icon(Icons.lan_outlined, size: 15, color: AppColors.textSubtle),
            const SizedBox(width: 8),
            Text(
              'Local IP',
              style: TextStyle(
                color: AppColors.textSubtle,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        );
      },
    );
  }
}

// ── Tool grid models / widgets ────────────────────────────────────────────────

class _ToolItem {
  const _ToolItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool});

  final _ToolItem tool;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: tool.onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(tool.icon, size: 34),
              const Spacer(),
              Text(
                tool.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tool.subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
