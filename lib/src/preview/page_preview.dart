import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minterm_view/minterm_view.dart';

/// Ce que le serveur enverrait au terminal pour afficher [page] : l'écran
/// d'initialisation du service, puis la page. Les fichiers `affiche` ne sont
/// pas lus (le navigateur n'a pas accès aux fichiers du service) : ceux qui
/// manquent sont listés dans [missing].
class PagePreviewData {
  PagePreviewData(this.minitel, this.missing, this.error);

  /// Le terminal Minitel, avec la page affichée.
  final TMinitel minitel;

  /// Les fichiers `affiche` que la page demande et que l'éditeur n'a pas.
  final List<String> missing;

  /// Pourquoi la page n'a pas pu être rendue, ou `null`.
  final String? error;
}

/// Rend [page] du [service] dans un nouveau terminal Minitel.
PagePreviewData renderPreview(
  Service service,
  ServicePage page, {
  Map<String, String> variables = const {},
  DateTime? now,
}) {
  final missing = <String>[];
  Uint8List assets(String path) {
    if (!missing.contains(path)) missing.add(path);
    return Uint8List(0);
  }

  final minitel = TMinitel();
  String? error;
  try {
    final time = now ?? DateTime.now();
    final init = VideotexWriter();
    renderScreen(
      service.initScreen,
      init,
      assets: assets,
      now: time,
      variables: variables,
      init: service.initScreen,
    );
    minitel.emulate(init.takeBytes());
    final rendered = renderPage(
      page,
      assets: assets,
      now: time,
      variables: variables,
      init: service.initScreen,
    );
    minitel.emulate(rendered.bytes);
  } on Object catch (e) {
    error = e is ServiceException ? e.message : '$e';
  }
  return PagePreviewData(minitel, missing, error);
}

/// L'aperçu d'une page : son écran Minitel, tel que le serveur l'afficherait.
class PagePreview extends StatelessWidget {
  const PagePreview({
    super.key,
    required this.service,
    required this.page,
    this.width = 400,
    this.large = false,
    this.color = false,
    this.onColorChanged,
    this.variables = const {},
  });

  final Service service;
  final String page;
  final double width;

  /// Remplit la place disponible : l'écran en grand, les notes dessous.
  final bool large;

  /// Couleur ou niveaux de gris (par défaut, gris).
  final bool color;
  final ValueChanged<bool>? onColorChanged;

  /// Les valeurs de test des variables `${nom}`.
  final Map<String, String> variables;

  @override
  Widget build(BuildContext context) {
    final servicePage = service.pages[page];
    if (servicePage == null) return const SizedBox.shrink();
    final data = renderPreview(service, servicePage, variables: variables);
    final theme = Theme.of(context);
    final palette = color ? MinColors : MinGrey;
    final toggle = onColorChanged == null
        ? const SizedBox.shrink()
        : IconButton(
            key: const Key('preview-colors'),
            tooltip: color
                ? 'Couleur (passer en niveaux de gris)'
                : 'Niveaux de gris (passer en couleur)',
            isSelected: color,
            icon: const Icon(Icons.palette_outlined),
            selectedIcon: const Icon(Icons.palette),
            onPressed: () => onColorChanged!(!color),
          );
    final notes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (data.error != null)
          Text(
            'Page non rendue : ${data.error}',
            key: const Key('preview-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (data.missing.isNotEmpty)
          Text(
            'Fichiers « affiche » non montrés (l\'éditeur n\'a pas les '
            'fichiers du service) : ${data.missing.join(', ')}.',
            key: const Key('preview-missing'),
          ),
        Text(
          'Les données de la page (messages, compteurs…) ne sont pas '
          'chargées. Les variables prennent les valeurs des données de test.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
    if (large) {
      return Column(
        children: [
          Expanded(
            child: Container(
              key: const Key('preview-screen'),
              color: Colors.black,
              alignment: Alignment.center,
              child: MinitelView(minitel: data.minitel, colors: palette),
            ),
          ),
          Padding(padding: const EdgeInsets.all(8), child: notes),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const Key('preview-screen'),
          width: width,
          color: Colors.black,
          child: MinitelView(minitel: data.minitel, colors: palette),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [toggle, notes],
          ),
        ),
      ],
    );
  }
}
