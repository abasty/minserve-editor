import 'package:flutter/material.dart';

/// Une poignée qu'on tire pour redimensionner deux volets : verticale (entre
/// deux volets côte à côte) ou horizontale (entre deux volets l'un sur l'autre).
class SplitHandle extends StatefulWidget {
  const SplitHandle({
    super.key,
    required this.axis,
    required this.onStart,
    required this.onDrag,
  });

  /// [Axis.horizontal] : volets côte à côte (la poignée est une barre verticale
  /// qu'on tire à droite ou à gauche) ; [Axis.vertical] : volets l'un sur
  /// l'autre.
  final Axis axis;

  /// Début d'un déplacement : le moment de lire la taille actuelle.
  final VoidCallback onStart;

  /// Déplacement en pixels depuis le début (positif : vers la droite ou vers
  /// le bas).
  final ValueChanged<double> onDrag;

  /// Épaisseur de la poignée.
  static const thickness = 8.0;

  @override
  State<SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<SplitHandle> {
  bool _active = false;
  double _total = 0;

  @override
  Widget build(BuildContext context) {
    final side = widget.axis == Axis.horizontal;
    final scheme = Theme.of(context).colorScheme;
    final lit = _active;
    final bar = Container(
      width: side ? (lit ? 3 : 1) : null,
      height: side ? null : (lit ? 3 : 1),
      color: lit ? scheme.primary : scheme.outlineVariant,
    );
    return MouseRegion(
      cursor: side
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: side
            ? (_) {
                _total = 0;
                widget.onStart();
              }
            : null,
        onHorizontalDragUpdate: side
            ? (d) {
                _total += d.delta.dx;
                widget.onDrag(_total);
              }
            : null,
        onVerticalDragStart: side
            ? null
            : (_) {
                _total = 0;
                widget.onStart();
              },
        onVerticalDragUpdate: side
            ? null
            : (d) {
                _total += d.delta.dy;
                widget.onDrag(_total);
              },
        child: SizedBox(
          width: side ? SplitHandle.thickness : null,
          height: side ? null : SplitHandle.thickness,
          child: Center(child: bar),
        ),
      ),
    );
  }
}
