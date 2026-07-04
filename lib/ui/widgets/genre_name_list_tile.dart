import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../util/focus/dpad_keys.dart';
import '../mixins/focus_state_mixin.dart';

class GenreListItem {
  final String id;
  final String name;

  GenreListItem({required this.id, required this.name});
}

class GenreNameListTile extends StatefulWidget {
  final GenreListItem genre;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;

  const GenreNameListTile({
    super.key,
    required this.genre,
    required this.selected,
    required this.onTap,
    this.onFocusChange,
  });

  @override
  State<GenreNameListTile> createState() => _GenreNameListTileState();
}

class _GenreNameListTileState extends State<GenreNameListTile>
    with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.selected || showFocusBorder;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: Focus(
        onFocusChange: (focused) {
          setFocused(focused);
          widget.onFocusChange?.call(focused);
        },
        onKeyEvent: (_, event) {
          if (isActivateKey(event)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isHighlighted
                ? AppColorScheme.accent.withAlpha(40)
                : Colors.transparent,
            child: Text(
              widget.genre.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
                color: AppColorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
