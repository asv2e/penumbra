import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:hive_flutter/hive_flutter.dart';

/// Summary of a saved project. [edit] is the JSON from `editToJson`.
class ProjectMeta {
  ProjectMeta({
    required this.id,
    required this.name,
    required this.created,
    required this.updated,
    required this.sourceName,
    this.overlays = const {},
    this.edit = const {},
  });

  final String id;
  final String name;
  final DateTime created;
  final DateTime updated;

  /// File name of the original photo (its extension picks the decoder).
  final String sourceName;

  /// Double-exposure images: overlay id -> original file name.
  final Map<int, String> overlays;
  final Map<String, dynamic> edit;

  ProjectMeta copyWith({
    String? name,
    DateTime? updated,
    Map<int, String>? overlays,
    Map<String, dynamic>? edit,
  }) =>
      ProjectMeta(
        id: id,
        name: name ?? this.name,
        created: created,
        updated: updated ?? this.updated,
        sourceName: sourceName,
        overlays: overlays ?? this.overlays,
        edit: edit ?? this.edit,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': created.millisecondsSinceEpoch,
        'updated': updated.millisecondsSinceEpoch,
        'source': sourceName,
        'overlays': {for (final e in overlays.entries) '${e.key}': e.value},
        'edit': edit,
      };

  static ProjectMeta? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String) return null;
    DateTime t(Object? v) => DateTime.fromMillisecondsSinceEpoch(v is num ? v.toInt() : 0);
    final ov = <int, String>{};
    final rawOv = j['overlays'];
    if (rawOv is Map) {
      rawOv.forEach((k, v) {
        final n = int.tryParse('$k');
        if (n != null && v is String) ov[n] = v;
      });
    }
    return ProjectMeta(
      id: id,
      name: j['name'] is String ? j['name'] as String : 'Untitled',
      created: t(j['created']),
      updated: t(j['updated']),
      sourceName: j['source'] is String ? j['source'] as String : 'photo.jpg',
      overlays: ov,
      edit: j['edit'] is Map ? Map<String, dynamic>.from(j['edit'] as Map) : const {},
    );
  }
}

/// Projects saved inside the app. Hive keeps them in IndexedDB on web and in
/// the app's documents folder elsewhere, so the same code runs everywhere.
///
/// Layout:
///   projects       id -> meta + edit JSON (small, kept in memory)
///   project_thumbs id -> JPEG thumbnail
///   project_files  "id/src" original file bytes, "id/ov/N" overlay file bytes
///                  (lazy box: read from disk only when a project is opened)
class ProjectStore {
  ProjectStore._();
  static final ProjectStore instance = ProjectStore._();

  /// Bumped after every write so the project list can refresh itself.
  final ValueNotifier<int> revision = ValueNotifier(0);

  bool available = false;
  late Box<String> _meta;
  late Box<Uint8List> _thumbs;
  late LazyBox<Uint8List> _files;

  Future<void> init() async {
    try {
      await Hive.initFlutter();
      _meta = await Hive.openBox<String>('projects');
      _thumbs = await Hive.openBox<Uint8List>('project_thumbs');
      _files = await Hive.openLazyBox<Uint8List>('project_files');
      available = true;
    } catch (_) {
      available = false;
    }
  }

  void _changed() => revision.value++;

  String _srcKey(String id) => '$id/src';
  String _ovKey(String id, int n) => '$id/ov/$n';

  List<ProjectMeta> list() {
    if (!available) return const [];
    final out = <ProjectMeta>[];
    for (final raw in _meta.values) {
      try {
        final m = ProjectMeta.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (m != null) out.add(m);
      } catch (_) {}
    }
    out.sort((a, b) => b.updated.compareTo(a.updated));
    return out;
  }

  ProjectMeta? get(String id) {
    if (!available) return null;
    final raw = _meta.get(id);
    if (raw == null) return null;
    try {
      return ProjectMeta.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Uint8List? thumb(String id) => available ? _thumbs.get(id) : null;

  Future<Uint8List?> readSource(String id) async => available ? _files.get(_srcKey(id)) : null;
  Future<Uint8List?> readOverlay(String id, int n) async => available ? _files.get(_ovKey(id, n)) : null;

  Future<String> create({required String name, required String sourceName, required Uint8List bytes}) async {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await _files.put(_srcKey(id), bytes);
    final now = DateTime.now();
    final meta = ProjectMeta(id: id, name: name, created: now, updated: now, sourceName: sourceName);
    await _meta.put(id, jsonEncode(meta.toJson()));
    _changed();
    return id;
  }

  Future<void> putOverlay(String id, int n, Uint8List bytes) => _files.put(_ovKey(id, n), bytes);

  /// Writes the current edit. Does nothing if the project was deleted meanwhile.
  Future<void> saveEdit(
    String id, {
    required Map<String, dynamic> edit,
    required Map<int, String> overlays,
    String? name,
    Uint8List? thumb,
  }) async {
    final cur = get(id);
    if (cur == null) return;
    final next = cur.copyWith(name: name, updated: DateTime.now(), overlays: overlays, edit: edit);
    await _meta.put(id, jsonEncode(next.toJson()));
    if (thumb != null) await _thumbs.put(id, thumb);
    _changed();
  }

  Future<void> rename(String id, String name) async {
    final cur = get(id);
    if (cur == null) return;
    await _meta.put(id, jsonEncode(cur.copyWith(name: name).toJson()));
    _changed();
  }

  Future<void> delete(String id) async {
    await _meta.delete(id);
    await _thumbs.delete(id);
    final keys = _files.keys.where((k) => k is String && k.startsWith('$id/')).toList();
    await _files.deleteAll(keys);
    _changed();
  }

  Future<String?> duplicate(String id) async {
    final cur = get(id);
    final src = await readSource(id);
    if (cur == null || src == null) return null;
    final newId = await create(name: '${cur.name} copy', sourceName: cur.sourceName, bytes: src);
    for (final n in cur.overlays.keys) {
      final b = await readOverlay(id, n);
      if (b != null) await putOverlay(newId, n, b);
    }
    final t = _thumbs.get(id);
    await saveEdit(newId, edit: cur.edit, overlays: cur.overlays, name: '${cur.name} copy', thumb: t);
    return newId;
  }
}
