import 'package:minserve_core/minserve_core.dart';

/// Ce qui provoque une transition.
enum EdgeKind {
  /// Une règle de `action` : saisie + touche.
  rule,

  /// La fin d'un programme `exec` (`suivant`).
  exec,

  /// Le renvoi d'une page réservée à un visiteur non connecté (`acces.sinon`).
  access,
}

/// Une transition d'une page vers une autre. Plusieurs règles entre les mêmes
/// deux pages ne font qu'une arête, avec plusieurs [labels].
class GraphEdge {
  GraphEdge(this.from, this.to, this.kind);

  final String from;
  final String to;
  final EdgeKind kind;

  /// Ce qui déclenche la transition, une entrée par règle (`1 · ENVOI`).
  final List<String> labels = [];

  /// Vrai si toutes les règles de l'arête ont une condition `si`.
  bool conditional = true;

  bool get isLoop => from == to;
}

/// Ce qui vaut sur toute page : un raccourci, la touche GUIDE, la page de
/// changement de mot de passe.
enum GlobalKind { shortcut, guide, passwordChange }

class GlobalLink {
  const GlobalLink(this.kind, this.to, this.label);

  final GlobalKind kind;
  final String to;
  final String label;
}

/// Une page du service, avec ce que le graphe en montre.
class GraphNode {
  GraphNode({
    required this.name,
    required this.isStart,
    required this.hasInput,
    required this.program,
    required this.requiresLogin,
    required this.implicitLogin,
  });

  final String name;
  final bool isStart;
  final bool hasInput;

  /// Programme `exec` de la page (`prog`), `null` si elle n'en lance pas.
  final String? program;

  /// La page n'est affichée qu'à un utilisateur connecté.
  final bool requiresLogin;

  /// ...parce que c'est le défaut d'une page `exec`, pas un `acces` écrit.
  final bool implicitLogin;

  /// Aucun parcours du service n'y mène (même avec les liens globaux).
  bool unreachable = false;

  bool get isProgram => program != null;
}

/// Les pages d'un service et leurs transitions, calculées à partir du service
/// lu par le serveur : un service accepté par le serveur donne un graphe.
class ServiceGraph {
  ServiceGraph._(this.nodes, this.edges, this.globals, this.start);

  final Map<String, GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<GlobalLink> globals;
  final String start;

  factory ServiceGraph.of(Service service) {
    final nodes = <String, GraphNode>{};
    for (final page in service.pages.values) {
      final access = page.access;
      nodes[page.name] = GraphNode(
        name: page.name,
        isStart: page.name == service.start,
        hasInput: page.input != null,
        program: page.exec?.prog,
        requiresLogin: access.requiresLogin,
        implicitLogin: access.requiresLogin && access.implicit,
      );
    }

    final byKey = <(String, String, EdgeKind), GraphEdge>{};
    void add(
      String from,
      String to,
      EdgeKind kind,
      String label, {
      bool conditional = false,
    }) {
      final edge = byKey.putIfAbsent((
        from,
        to,
        kind,
      ), () => GraphEdge(from, to, kind));
      if (!edge.labels.contains(label)) edge.labels.add(label);
      if (!conditional) edge.conditional = false;
    }

    for (final page in service.pages.values) {
      for (final choice in page.action?.choices ?? const <Choice>[]) {
        add(
          page.name,
          choice.next,
          EdgeKind.rule,
          choiceLabel(choice),
          conditional: choice.condition != null,
        );
      }
      final next = page.exec?.next;
      if (next != null) add(page.name, next, EdgeKind.exec, 'fin du programme');
      final otherwise = page.access.otherwise;
      if (otherwise != null) {
        add(page.name, otherwise, EdgeKind.access, 'non connecté');
      }
    }
    final edges = byKey.values.toList();

    final globals = <GlobalLink>[
      for (final c in service.shortcuts)
        GlobalLink(GlobalKind.shortcut, c.next, choiceLabel(c)),
      if (service.guide != null)
        GlobalLink(GlobalKind.guide, service.guide!, 'GUIDE'),
      if (service.passwordChangePage != null)
        GlobalLink(
          GlobalKind.passwordChange,
          service.passwordChangePage!,
          'mot de passe à changer',
        ),
    ];

    // Atteintes : depuis la page de départ, en suivant les transitions ; les
    // cibles des liens globaux le sont toujours (depuis n'importe quelle page).
    final reached = <String>{};
    final queue = [service.start, for (final g in globals) g.to];
    while (queue.isNotEmpty) {
      final name = queue.removeLast();
      if (!nodes.containsKey(name) || !reached.add(name)) continue;
      for (final e in edges) {
        if (e.from == name) queue.add(e.to);
      }
    }
    for (final node in nodes.values) {
      node.unreachable = !reached.contains(node.name);
    }
    return ServiceGraph._(nodes, edges, globals, service.start);
  }

  /// Les transitions qui partent de [name].
  Iterable<GraphEdge> outgoing(String name) =>
      edges.where((e) => e.from == name);

  /// Les transitions qui arrivent à [name].
  Iterable<GraphEdge> incoming(String name) => edges.where((e) => e.to == name);

  /// Pages sans entrée ni programme : l'écran s'affiche, puis plus aucune
  /// touche n'a d'effet.
  List<String> get deadEnds => [
    for (final n in nodes.values)
      if (!n.hasInput && !n.isProgram) n.name,
  ];

  /// Pages que rien n'atteint.
  List<String> get unreachable => [
    for (final n in nodes.values)
      if (n.unreachable) n.name,
  ];

  /// Pages dont le programme se termine sans page suivante (la voie se ferme).
  List<String> get closing => [
    for (final n in nodes.values)
      if (n.isProgram && outgoing(n.name).every((e) => e.kind != EdgeKind.exec))
        n.name,
  ];
}

/// Le texte d'une règle : la saisie et la touche, plus l'action de compte ou de
/// message qu'elle déclenche.
String choiceLabel(Choice c) {
  final key = c.key.name.toUpperCase();
  final base = c.value == null ? key : '${c.value} · $key';
  final action = [
    if (c.login != null) 'connexion',
    if (c.register != null) 'inscription',
    if (c.changePassword != null) 'mot de passe',
    if (c.message != null) 'message',
    if (c.logout) 'déconnexion',
  ];
  return action.isEmpty ? base : '$base (${action.join(', ')})';
}
