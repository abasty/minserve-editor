import 'package:flutter/material.dart';
import 'package:minterm_view/minterm_view.dart';

import '../assets.dart';

/// Demande un fichier du dossier assets : la liste (filtrable) à gauche, l'écran
/// Videotex du fichier choisi à droite. Rend son chemin, ou `null` si on annule.
Future<String?> askAsset(
  BuildContext context,
  AssetSource source, {
  String? current,
}) => showDialog<String>(
  context: context,
  builder: (context) => _AssetDialog(source, current),
);

class _AssetDialog extends StatefulWidget {
  const _AssetDialog(this.source, this.current);

  final AssetSource source;
  final String? current;

  @override
  State<_AssetDialog> createState() => _AssetDialogState();
}

class _AssetDialogState extends State<_AssetDialog> {
  late final List<String> _all = widget.source.list();
  String _filter = '';
  String? _chosen;
  bool _color = false;

  @override
  void initState() {
    super.initState();
    if (widget.current != null && _all.contains(widget.current)) {
      _chosen = widget.current;
    }
  }

  List<String> get _shown {
    final f = _filter.trim().toLowerCase();
    return [
      for (final p in _all)
        if (f.isEmpty || p.toLowerCase().contains(f)) p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;
    return AlertDialog(
      title: const Text('Choisir un fichier'),
      content: SizedBox(
        width: 720,
        height: 380,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('asset-filter'),
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Filtrer',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.source.label,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Expanded(
                    child: shown.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _all.isEmpty
                                  ? 'Aucun fichier dans ce dossier.'
                                  : 'Aucun fichier ne correspond.',
                              key: const Key('asset-none'),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final p in shown)
                                ListTile(
                                  key: Key('asset-$p'),
                                  dense: true,
                                  selected: p == _chosen,
                                  selectedTileColor: scheme.secondaryContainer,
                                  title: Text(p),
                                  onTap: () => setState(() => _chosen = p),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 320, child: _preview()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('dialog-ok'),
          onPressed: _chosen == null
              ? null
              : () => Navigator.pop(context, _chosen),
          child: const Text('Choisir'),
        ),
      ],
    );
  }

  Widget _preview() {
    final path = _chosen;
    if (path == null) {
      return const Center(child: Text('Choisissez un fichier.'));
    }
    final TMinitel minitel;
    final int size;
    try {
      final bytes = widget.source.read(path);
      size = bytes.length;
      minitel = TMinitel()..emulate(bytes);
    } on AssetException catch (e) {
      return Text(
        e.message,
        key: const Key('asset-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const Key('asset-preview'),
          color: Colors.black,
          child: MinitelView(
            minitel: minitel,
            colors: _color ? MinColors : MinGrey,
          ),
        ),
        Row(
          children: [
            Expanded(child: Text('$size octets')),
            IconButton(
              key: const Key('asset-colors'),
              tooltip: _color
                  ? 'Couleur (passer en niveaux de gris)'
                  : 'Niveaux de gris (passer en couleur)',
              isSelected: _color,
              icon: const Icon(Icons.palette_outlined),
              selectedIcon: const Icon(Icons.palette),
              onPressed: () => setState(() => _color = !_color),
            ),
          ],
        ),
      ],
    );
  }
}
