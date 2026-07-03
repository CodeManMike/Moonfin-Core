import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../adaptive/adaptive_glass.dart';
import '../focus/focus_theme.dart';

class SleepTimerIndicator extends StatelessWidget {
  final String label;
  final VoidCallback onCancel;
  final FocusNode? focusNode;

  const SleepTimerIndicator({
    super.key,
    required this.label,
    required this.onCancel,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCancel,
        borderRadius: AppRadius.circular(_capsuleRadius),
        child: Container(
          decoration: FocusTheme.focusDecoration(
            isFocused: true,
            radius: _capsuleRadius,
            color: AppColorScheme.accent,
          ),
          child: adaptiveGlass(
            cornerRadius: _capsuleRadius,
            blur: 24,
            fallbackColor: AppColorScheme.surface.withValues(alpha: 0.55),
            tint: AppColorScheme.surface.withValues(alpha: 0.18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bedtime,
                    color: AppColorScheme.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.close_rounded,
                    color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const double _capsuleRadius = 28;
