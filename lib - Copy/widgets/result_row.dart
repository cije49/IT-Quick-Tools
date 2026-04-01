import 'package:flutter/material.dart';
import '../core/app_constants.dart';

/// A two-column label / value row used in result cards throughout the app.
///
/// The [value] text is selectable so users can long-press to copy individual
/// fields without needing to copy the whole result.
class ResultRow extends StatelessWidget {
  const ResultRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;

  /// Optional override for the value text colour (e.g. green for OPEN,
  /// red for CLOSED). Defaults to [Colors.white].
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: SelectableText(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
