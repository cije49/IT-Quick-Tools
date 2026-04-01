import 'package:flutter/material.dart';

/// Central place for every magic colour / value used across the app.
/// Import this instead of scattering hex literals through the codebase.
///
/// NOTE: Fields that reference [Colors] members (e.g. [Colors.white70]) must
/// be `static final` rather than `static const` because those members are
/// not compile-time constants in Flutter's framework.
abstract final class AppColors {
  // ── Backgrounds ─────────────────────────────────────────────────────────────
  static const Color scaffold    = Color(0xFF0B1220);
  static const Color card        = Color(0xFF111827);
  static const Color input       = Color(0xFF0F172A);
  static const Color chipBg      = Color(0xFF1E293B);
  static const Color chipSelected= Color(0xFF2563EB);

  // ── Borders ──────────────────────────────────────────────────────────────────
  static const Color borderDefault = Color(0xFF1F2937);
  static const Color borderInput   = Color(0xFF334155);
  static const Color borderFocused = Color(0xFF60A5FA);

  // ── Text  (final, not const – Colors.whiteXX are not compile-time const) ────
  static final Color textMuted       = Colors.white70;
  static final Color textSubtle      = Colors.white54;
  static final Color textPlaceholder = Colors.white38;

  // ── Status colours ───────────────────────────────────────────────────────────
  static const Color statusOpen   = Color(0xFF22C55E); // green-500
  static const Color statusClosed = Color(0xFFEF4444); // red-500
  static const Color statusError  = Color(0xFFF59E0B); // amber-500

  // ── Brand / seed ─────────────────────────────────────────────────────────────
  static const Color seed = Color(0xFF3B82F6);
}

abstract final class AppKeys {
  static const String savedCustomPorts  = 'saved_custom_ports';
  static const String savedWifiProfiles = 'saved_wifi_profiles';
}
