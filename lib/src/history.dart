import 'package:flutter/widgets.dart';

/// Le texte à un instant, avec la sélection.
class Snapshot {
  const Snapshot(this.text, this.selection);

  final String text;
  final TextSelection selection;
}

/// L'historique des textes, pour défaire et refaire : celui de la frappe et
/// celui des modifications du graphe sont une seule pile.
class EditHistory {
  EditHistory({this.limit = 200});

  /// Nombre maximal d'étapes gardées (les plus anciennes sont oubliées).
  final int limit;

  final _undo = <Snapshot>[];
  final _redo = <Snapshot>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Note l'état [before] d'avant une modification : on pourra y revenir.
  void record(Snapshot before) {
    _undo.add(before);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  /// L'état à rétablir pour défaire, ou `null` ; [current] est gardé pour
  /// refaire.
  Snapshot? undo(Snapshot current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  Snapshot? redo(Snapshot current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
