import 'dart:math';
import 'dart:ui';

import 'service_graph.dart';

const nodeWidth = 150.0;
const nodeHeight = 52.0;
const gapX = 90.0;
const gapY = 26.0;
const bandGap = 70.0;
const margin = 30.0;

/// Où chaque page est dessinée.
class GraphLayout {
  GraphLayout(this.rects, this.layers, this.size);

  /// Rectangle de chaque page.
  final Map<String, Rect> rects;

  /// Colonne de chaque page (0 : départ de sa bande).
  final Map<String, int> layers;
  final Size size;

  /// Une transition qui revient en arrière ou reste dans sa colonne.
  bool isBack(GraphEdge e) => layers[e.to]! <= layers[e.from]!;
}

/// Dispose les pages en colonnes, de gauche à droite.
///
/// Une colonne est un nombre de transitions depuis la page de départ (au plus
/// court). Les pages que le départ n'atteint pas forment des bandes en dessous,
/// chacune partant d'une page que rien ne cible, sinon de la première restante.
/// Dans une colonne, les pages sont ordonnées pour rapprocher chacune de ses
/// voisines des colonnes voisines (moyenne des positions, quelques passes).
GraphLayout layoutGraph(ServiceGraph graph) {
  final names = graph.nodes.keys.toList();
  final out = <String, List<String>>{for (final n in names) n: []};
  final adj = <String, List<String>>{for (final n in names) n: []};
  for (final e in graph.edges) {
    if (e.isLoop || !out.containsKey(e.from) || !out.containsKey(e.to)) {
      continue;
    }
    out[e.from]!.add(e.to);
    adj[e.from]!.add(e.to);
    adj[e.to]!.add(e.from);
  }

  final layers = <String, int>{};
  final bands = <List<List<String>>>[]; // bande -> colonne -> pages

  void grow(String root) {
    final band = <List<String>>[];
    final queue = [root];
    layers[root] = 0;
    while (queue.isNotEmpty) {
      final name = queue.removeAt(0);
      final layer = layers[name]!;
      while (band.length <= layer) {
        band.add([]);
      }
      band[layer].add(name);
      for (final next in out[name]!) {
        if (layers.containsKey(next)) continue;
        layers[next] = layer + 1;
        queue.add(next);
      }
    }
    bands.add(band);
  }

  if (graph.nodes.containsKey(graph.start)) grow(graph.start);
  final hasIncoming = {
    for (final e in graph.edges)
      if (!e.isLoop) e.to,
  };
  for (final name in names) {
    if (!layers.containsKey(name) && !hasIncoming.contains(name)) grow(name);
  }
  for (final name in names) {
    if (!layers.containsKey(name)) grow(name);
  }

  final rects = <String, Rect>{};
  var top = margin;
  var width = 0.0;
  for (final band in bands) {
    _order(band, adj);
    final tallest = band.fold<int>(0, (m, c) => max(m, c.length));
    final height = tallest * nodeHeight + (tallest - 1) * gapY;
    for (var x = 0; x < band.length; x++) {
      final column = band[x];
      final used = column.length * nodeHeight + (column.length - 1) * gapY;
      var y = top + (height - used) / 2;
      for (final name in column) {
        final left = margin + x * (nodeWidth + gapX);
        rects[name] = Rect.fromLTWH(left, y, nodeWidth, nodeHeight);
        y += nodeHeight + gapY;
        width = max(width, left + nodeWidth);
      }
    }
    top += height + bandGap;
  }
  return GraphLayout(
    rects,
    layers,
    Size(width + margin, max(top - bandGap, 0) + margin),
  );
}

/// Ordonne chaque colonne d'après la position moyenne des voisines des
/// colonnes voisines, en descendant puis en remontant.
void _order(List<List<String>> band, Map<String, List<String>> adj) {
  if (band.length < 2) return;
  final position = <String, double>{};
  void record() {
    for (final column in band) {
      for (var i = 0; i < column.length; i++) {
        position[column[i]] = i.toDouble();
      }
    }
  }

  void sweep(int x, int neighbour) {
    final column = band[x];
    final layer = {for (final c in band[neighbour]) c};
    final score = <String, double>{};
    for (var i = 0; i < column.length; i++) {
      final ps = [
        for (final n in adj[column[i]]!)
          if (layer.contains(n)) position[n]!,
      ];
      score[column[i]] = ps.isEmpty
          ? i.toDouble()
          : ps.reduce((a, b) => a + b) / ps.length;
    }
    final index = {for (var i = 0; i < column.length; i++) column[i]: i};
    column.sort((a, b) {
      final c = score[a]!.compareTo(score[b]!);
      return c != 0 ? c : index[a]!.compareTo(index[b]!);
    });
    record();
  }

  record();
  for (var pass = 0; pass < 4; pass++) {
    for (var x = 1; x < band.length; x++) {
      sweep(x, x - 1);
    }
    for (var x = band.length - 2; x >= 0; x--) {
      sweep(x, x + 1);
    }
  }
}
