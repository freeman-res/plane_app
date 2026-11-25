import 'package:material_ui/material_ui.dart';

import 'note.dart';

/// Keeps formatting attached to text as the user types or replaces a selection.
class NoteTextController extends TextEditingController {
  NoteTextController(List<NoteSpan> initial)
    : _spans = List.of(initial.where((span) => span.text.isNotEmpty)),
      _previousText = initial.map((span) => span.text).join() {
    text = _previousText;
    addListener(_syncText);
  }

  List<NoteSpan> _spans;
  String _previousText;
  NoteSpan _typingStyle = const NoteSpan(text: '');
  bool _pendingStyle = false;

  List<NoteSpan> get spans => List.unmodifiable(_spans);

  List<NoteSpan> _slice(int start, int end) {
    final result = <NoteSpan>[];
    var offset = 0;
    for (final span in _spans) {
      final left = start > offset ? start - offset : 0;
      final right = end < offset + span.text.length
          ? end - offset
          : span.text.length;
      if (left < right)
        result.add(span.copyWith(text: span.text.substring(left, right)));
      offset += span.text.length;
      if (offset >= end) break;
    }
    return result;
  }

  NoteSpan _styleAt(int offset) {
    var position = 0;
    for (final span in _spans) {
      position += span.text.length;
      if (offset < position) return span;
    }
    return _spans.isEmpty ? _typingStyle : _spans.last;
  }

  void _syncText() {
    final current = text;
    if (current == _previousText) return;
    var prefix = 0;
    while (prefix < current.length &&
        prefix < _previousText.length &&
        current.codeUnitAt(prefix) == _previousText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < current.length - prefix &&
        suffix < _previousText.length - prefix &&
        current.codeUnitAt(current.length - suffix - 1) ==
            _previousText.codeUnitAt(_previousText.length - suffix - 1)) {
      suffix++;
    }
    final inserted = current.substring(prefix, current.length - suffix);
    final style = _pendingStyle || _previousText.isEmpty || _spans.isEmpty
        ? _typingStyle
        : _styleAt(prefix > 0 ? prefix - 1 : 0);
    _pendingStyle = false;
    _spans = [
      ..._slice(0, prefix),
      if (inserted.isNotEmpty) style.copyWith(text: inserted),
      ..._slice(_previousText.length - suffix, _previousText.length),
    ];
    _compact();
    _previousText = current;
  }

  void _compact() {
    final result = <NoteSpan>[];
    for (final span in _spans) {
      if (span.text.isEmpty) continue;
      if (result.isNotEmpty) {
        final previous = result.last;
        if (previous.fontFamily == span.fontFamily &&
            previous.fontSize == span.fontSize &&
            previous.bold == span.bold &&
            previous.italic == span.italic &&
            previous.underline == span.underline &&
            previous.color == span.color) {
          result[result.length - 1] = previous.copyWith(
            text: previous.text + span.text,
          );
          continue;
        }
      }
      result.add(span);
    }
    _spans = result;
  }

  void format(NoteSpan Function(NoteSpan) transform) {
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    if (start == end) {
      _typingStyle = transform(_styleAt(start > 0 ? start - 1 : start));
      _pendingStyle = true;
      notifyListeners();
      return;
    }
    _spans = [
      ..._slice(0, start),
      for (final span in _slice(start, end)) transform(span),
      ..._slice(end, text.length),
    ];
    _compact();
    notifyListeners();
  }

  NoteSpan get currentStyle {
    if (_pendingStyle) return _typingStyle;
    if (!selection.isValid) return _typingStyle;
    return _styleAt(selection.start.clamp(0, text.length));
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => TextSpan(
    style: style,
    children: [
      for (final span in _spans)
        TextSpan(
          text: span.text,
          style: TextStyle(
            fontFamily: switch (span.fontFamily) {
              'serif' => 'serif',
              'mono' => 'monospace',
              _ => null,
            },
            fontSize: span.fontSize.toDouble(),
            fontWeight: span.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
            decoration: span.underline ? TextDecoration.underline : null,
            color: span.color == null
                ? null
                : Color(
                    int.parse(span.color!.substring(1), radix: 16) | 0xFF000000,
                  ),
          ),
        ),
    ],
  );
}
