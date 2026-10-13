import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

/// Adds explicit remote-control endpoints to a native range slider on TV.
/// Touch and accessibility adjustment on the slider remain native.
class TvRangeSlider extends StatefulWidget {
  const TvRangeSlider({super.key, required this.child});

  final RangeSlider child;

  @override
  State<TvRangeSlider> createState() => _TvRangeSliderState();
}

class _TvRangeSliderState extends State<TvRangeSlider> {
  final _start = FocusNode(debugLabel: 'TV range lower endpoint');
  final _end = FocusNode(debugLabel: 'TV range upper endpoint');

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _adjust(bool start, bool increase) {
    final slider = widget.child;
    // Match the native semantic unit for discrete sliders.
    final step = (slider.max - slider.min) / (slider.divisions ?? 20);
    final old = start ? slider.values.start : slider.values.end;
    final value = (old + (increase ? step : -step))
        .clamp(
          start ? slider.min : slider.values.start,
          start ? slider.values.end : slider.max,
        )
        .toDouble();
    if ((value - old).abs() < 1e-9) return;
    slider.onChangeStart?.call(slider.values);
    final values = start
        ? RangeValues(value, slider.values.end)
        : RangeValues(slider.values.start, value);
    slider.onChanged?.call(values);
    slider.onChangeEnd?.call(values);
  }

  KeyEventResult _onKey(bool start, KeyEvent event) {
    final key = event.logicalKey;
    final horizontal = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final vertical = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    if (!horizontal && !vertical) return KeyEventResult.ignored;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (horizontal) {
        final rtl = Directionality.of(context) == TextDirection.rtl;
        _adjust(start, (key == LogicalKeyboardKey.arrowRight) != rtl);
      } else {
        (start ? _start : _end).focusInDirection(
          key == LogicalKeyboardKey.arrowUp
              ? TraversalDirection.up
              : TraversalDirection.down,
        );
      }
    }
    return KeyEventResult.handled;
  }

  Widget _endpoint(bool start) {
    final slider = widget.child;
    final value = start ? slider.values.start : slider.values.end;
    final label = start ? slider.labels?.start : slider.labels?.end;
    return Expanded(
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) => _onKey(start, event),
        child: TextButton(
          focusNode: start ? _start : _end,
          onPressed: slider.onChanged == null || slider.min == slider.max
              ? null
              : () => (start ? _end : _start).requestFocus(),
          child: Text(
              '${start ? '下限' : '上限'}：${label ?? value.toStringAsFixed(1)}'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) return widget.child;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeFocus(
            excluding: widget.child.onChanged == null ||
                widget.child.min == widget.child.max,
            child: Row(children: [_endpoint(true), _endpoint(false)])),
        const Text('左右调整 · 确认切换上下限 · 上下离开'),
        // Native range-slider focus nodes have no keyboard adjustment actions.
        ExcludeFocus(child: widget.child),
      ],
    );
  }
}
