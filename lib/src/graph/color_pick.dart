import 'package:flutter/material.dart';
import 'package:minserve_core/minserve_core.dart' show VideotexColor;
import 'package:minterm_view/minterm_view.dart' show MinColors, MinGrey;

/// Les huit couleurs, dans l'ordre des codes Vidéotex (celui de `MinColors`).
final colorNames = [for (final c in VideotexColor.values) c.frenchName];

/// Une couleur du Minitel : le carré est coupé en diagonale, la couleur en haut
/// à gauche et son niveau de gris en bas à droite, entourés de blanc pour se
/// voir sur un fond sombre comme sur un fond clair. [code] est le rang de la
/// couleur (0 noir ... 7 blanc), comme dans `MinColors`.
class ColorSwatchBox extends StatelessWidget {
  const ColorSwatchBox(this.code, {super.key, this.size = 16});

  final int code;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _SwatchPainter(code)),
  );
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.code);

  final int code;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final inner = Rect.fromLTWH(2, 2, w - 4, h - 4);
    canvas.save();
    canvas.clipRect(inner);
    canvas.drawPath(
      Path()
        ..moveTo(inner.left, inner.top)
        ..lineTo(inner.right, inner.top)
        ..lineTo(inner.left, inner.bottom)
        ..close(),
      Paint()..color = MinColors[code],
    );
    canvas.drawPath(
      Path()
        ..moveTo(inner.right, inner.top)
        ..lineTo(inner.right, inner.bottom)
        ..lineTo(inner.left, inner.bottom)
        ..close(),
      Paint()..color = MinGrey[code],
    );
    canvas.restore();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = Colors.black38,
    );
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.code != code;
}

/// Le choix d'une couleur : le champ montre la couleur choisie et son nom ; un
/// clic ouvre une palette de huit pastilles, dont le nom s'affiche au survol.
/// Si la couleur est facultative ([required] faux), une case permet de la
/// retirer.
class ColorPick extends StatelessWidget {
  const ColorPick({
    super.key,
    required this.value,
    required this.required,
    required this.onChanged,
    this.label,
    this.width = 150,
  });

  /// Le nom de la couleur, ou vide si elle n'est pas donnée.
  final String value;
  final bool required;

  /// Le nom de la nouvelle couleur, ou vide pour la retirer.
  final ValueChanged<String> onChanged;
  final String? label;
  final double width;

  Widget _cell(BuildContext context, String name, {required bool chosen}) {
    final code = colorNames.indexOf(name);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name.isEmpty ? 'aucune' : name,
      child: InkWell(
        key: Key('color-${name.isEmpty ? 'none' : name}'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => Navigator.pop(context, name),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: chosen ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: code < 0
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.block, size: 22, color: scheme.error),
                )
              : ColorSwatchBox(code, size: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = value.toLowerCase();
    final code = colorNames.indexOf(shown);
    return SizedBox(
      width: width,
      child: PopupMenuButton<String>(
        tooltip: '',
        position: PopupMenuPosition.under,
        padding: EdgeInsets.zero,
        onSelected: (v) {
          if (v != shown) onChanged(v);
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              width: 4 * 36.0,
              child: Wrap(
                children: [
                  for (final name in colorNames)
                    _cell(context, name, chosen: name == shown),
                  if (!required) _cell(context, '', chosen: shown.isEmpty),
                ],
              ),
            ),
          ),
        ],
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.arrow_drop_down),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
          ),
          child: Row(
            children: [
              if (code >= 0) ColorSwatchBox(code),
              if (code >= 0) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shown.isEmpty ? '—' : shown,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
