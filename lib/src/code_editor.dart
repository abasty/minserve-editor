import 'dart:math';

import 'package:flutter/material.dart';

/// Taille, interligne et police du texte : la hauteur d'une ligne est fixe
/// (`strut`), ce qui permet de numéroter les lignes et d'aller à une ligne.
/// La hauteur d'une ligne doit être un nombre entier de pixels (14 × 1,5 = 21) :
/// le navigateur arrondit sinon chaque ligne (19,5 → 20) et le surlignage
/// calculé à partir de 19,5 dérive de plus en plus vers le haut.
const _fontSize = 14.0;
const _lineHeight = 1.5;
const _lineExtent = _fontSize * _lineHeight;

/// Police embarquée (assets/fonts, licence Bitstream Vera) : dans le navigateur
/// les polices du système ne sont pas accessibles.
const _mono = 'DejaVuSansMono';

/// Commande pour aller à une ligne (à partir de 1) d'un [CodeEditor].
class CodeEditorController {
  void Function(int line)? _goTo;

  void goToLine(int line) => _goTo?.call(line);
}

/// Éditeur de texte brut : police fixe, numéros de ligne, pas de retour à la
/// ligne automatique (une ligne du YAML reste une ligne à l'écran).
class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.controller,
    this.commands,
    this.highlightLine,
  });

  final TextEditingController controller;
  final CodeEditorController? commands;

  /// Ligne (à partir de 1) à repérer, par exemple celle d'une erreur.
  final int? highlightLine;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.commands?._goTo = _goTo;
  }

  @override
  void didUpdateWidget(CodeEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    old.commands?._goTo = null;
    widget.commands?._goTo = _goTo;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.commands?._goTo = null;
    _vertical.dispose();
    _horizontal.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _goTo(int line) {
    final text = widget.controller.text;
    var offset = 0;
    for (var i = 1; i < line; i++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) break;
      offset = next + 1;
    }
    widget.controller.selection = TextSelection.collapsed(offset: offset);
    _focus.requestFocus();
    if (_vertical.hasClients) {
      final target = max(0.0, (line - 4) * _lineExtent);
      _vertical.animateTo(
        min(target, _vertical.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontFamily: _mono,
      fontSize: _fontSize,
      height: _lineHeight,
      color: scheme.onSurface,
    );
    final strut = StrutStyle(
      fontFamily: _mono,
      fontSize: _fontSize,
      height: _lineHeight,
      forceStrutHeight: true,
    );
    final lines = widget.controller.text.split('\n');
    final charWidth = _charWidth(style);
    final longest = lines.fold<int>(0, (m, l) => max(m, l.length));
    final gutterWidth = (lines.length.toString().length + 2) * charWidth;
    final bad = widget.highlightLine;

    return LayoutBuilder(
      builder: (context, box) {
        final textWidth = max(
          box.maxWidth - gutterWidth,
          (longest + 4) * charWidth,
        );
        return Scrollbar(
          controller: _vertical,
          child: SingleChildScrollView(
            controller: _vertical,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: gutterWidth,
                  color: scheme.surfaceContainerHighest,
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    [for (var i = 1; i <= lines.length; i++) i].join('\n'),
                    textAlign: TextAlign.right,
                    style: style.copyWith(color: scheme.onSurfaceVariant),
                    strutStyle: strut,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: Stack(
                      children: [
                        if (bad != null && bad >= 1 && bad <= lines.length)
                          Positioned(
                            top: (bad - 1) * _lineExtent,
                            left: 0,
                            right: 0,
                            height: _lineExtent,
                            child: ColoredBox(
                              color: scheme.errorContainer.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        SizedBox(
                          width: textWidth,
                          child: TextField(
                            key: const Key('code'),
                            controller: widget.controller,
                            focusNode: _focus,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            style: style,
                            strutStyle: strut,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.only(left: 6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _charWidth(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: '0' * 20, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width / 20;
    painter.dispose();
    return width;
  }
}
