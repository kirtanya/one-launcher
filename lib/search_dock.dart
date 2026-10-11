import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui/ds.dart';
import 'ui/motion.dart';

/// iOS-style search at the bottom of the screen. One white pill that morphs between:
/// - full bar ("Search 124 apps") while the list is at rest or scrolling back down,
/// - a round search button while the list is scrolled up,
/// - a live text field + close button while searching.
/// Sits above the keyboard when it's open.
class SearchDock extends StatelessWidget {
  const SearchDock({
    super.key,
    required this.compact,
    required this.active,
    required this.controller,
    required this.focus,
    required this.hint,
    required this.onActivate,
    required this.onClose,
    required this.onChanged,
    required this.onSubmitted,
  });

  final bool compact;
  final bool active;
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final VoidCallback onActivate, onClose;
  final ValueChanged<String> onChanged, onSubmitted;

  static const height = 56.0;
  static const shadow = [BoxShadow(color: Color(0x47000000), blurRadius: 24, offset: Offset(0, 8))];
  static const gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = math.max(mq.viewInsets.bottom, mq.padding.bottom) + DS.s12;
    final small = compact && !active;

    return Padding(
      padding: EdgeInsets.fromLTRB(DS.s16, 0, DS.s16, bottom),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            final width = active ? c.maxWidth - height - gap : (small ? height : c.maxWidth);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // The pill. Anchored to the right so it shrinks into a circle on the right.
                AnimatedPositioned(
                  duration: Motion.snapDuration,
                  curve: Motion.settle,
                  top: 0,
                  bottom: 0,
                  right: active ? height + gap : 0,
                  width: width,
                  child: _Pill(
                    small: small,
                    active: active,
                    controller: controller,
                    focus: focus,
                    hint: hint,
                    onActivate: onActivate,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                  ),
                ),
                // Close button slides in from the right while searching.
                AnimatedPositioned(
                  duration: Motion.snapDuration,
                  curve: Motion.snap,
                  top: 0,
                  bottom: 0,
                  right: active ? 0 : -(height + DS.s16),
                  width: height,
                  child: Pressable(
                    scale: .88,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: SearchDock.shadow),
                      child: Tooltip(
                        message: 'Close search',
                        child: Material(
                          color: DS.card,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onClose,
                            child: const Icon(Icons.close_rounded, color: DS.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.small,
    required this.active,
    required this.controller,
    required this.focus,
    required this.hint,
    required this.onActivate,
    required this.onChanged,
    required this.onSubmitted,
  });

  final bool small, active;
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final VoidCallback onActivate;
  final ValueChanged<String> onChanged, onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      enabled: !active,
      scale: .95,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), boxShadow: SearchDock.shadow),
        child: Material(
          color: DS.card,
          borderRadius: BorderRadius.circular(99),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: active ? null : onActivate,
            child: Stack(
              children: [
                // The icon never moves: 16 + 24 + 16 = 56, so it sits dead centre when the pill is a circle.
                const Positioned(left: 16, top: 16, child: Icon(Icons.search_rounded, color: DS.ink, size: 24)),
                Positioned(
                  left: 48,
                  right: DS.s16,
                  top: 0,
                  bottom: 0,
                  child: active
                      ? Center(
                          child: TextField(
                            controller: controller,
                            focusNode: focus,
                            onChanged: onChanged,
                            onSubmitted: onSubmitted,
                            textInputAction: TextInputAction.go,
                            autocorrect: false,
                            enableSuggestions: false,
                            cursorColor: DS.ink,
                            style: DS.rowTitle.copyWith(fontWeight: FontWeight.w500),
                            decoration: InputDecoration.collapsed(hintText: hint, hintStyle: DS.rowSub),
                          ),
                        )
                      : AnimatedOpacity(
                          duration: Motion.pressIn * 2,
                          opacity: small ? 0 : 1,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(hint, style: DS.rowSub.copyWith(fontSize: 16), maxLines: 1, softWrap: false, overflow: TextOverflow.clip),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
