import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog.dart';
import 'skin_index.dart';

/// A previously applied skin for one model, restored when the model loads.
class StoredDesign {
  const StoredDesign({required this.bytes, required this.tagId});

  final Uint8List bytes;
  final String? tagId;
}

/// File-system backed gallery + per-model design storage.
///
/// Layout under `<app documents>/skinstand/`:
///
/// ```text
/// index.json              gallery metadata
/// gallery/<id>.png        published screenshots
/// designs/<modelId>.png   last applied skin texture
/// designs/<modelId>.json  { tagId, savedAt }
/// ```
class SkinStore {
  SkinStore._(this._root, this._index);

  static const String _legacyPrefsKey = 'my_skins';
  static const String _lastModelPrefsKey = 'last_model_id';

  final Directory _root;
  final Random _random = Random();
  SkinIndex _index;

  List<SavedSkin> get skins => _index.items;

  Directory get _galleryDir => Directory('${_root.path}/gallery');
  Directory get _designDir => Directory('${_root.path}/designs');
  File get _indexFile => File('${_root.path}/index.json');

  static Future<SkinStore> open() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory root = Directory('${documents.path}/skinstand');
    await root.create(recursive: true);
    final SkinStore store = SkinStore._(root, SkinIndex.empty());
    await store._load();
    await store._migrateLegacy();
    return store;
  }

  /// Absolute path of a gallery image, or null when [file] is not a bare name.
  String? pathForFile(String file) {
    if (!RegExp(r'^[A-Za-z0-9_-]+\.png$').hasMatch(file)) {
      return null;
    }
    return '${_galleryDir.path}/$file';
  }

  Future<void> _load() async {
    await _galleryDir.create(recursive: true);
    await _designDir.create(recursive: true);

    if (!await _indexFile.exists()) {
      _index = SkinIndex.empty();
      return;
    }

    String source;
    try {
      source = await _indexFile.readAsString();
    } on FileSystemException catch (error) {
      debugPrint('SkinStore: cannot read index: $error');
      _index = SkinIndex.empty();
      return;
    }

    final SkinIndex parsed = SkinIndex.parse(source);
    bool malformed = false;
    try {
      final Object? decoded = jsonDecode(source);
      malformed = decoded is! Map<String, dynamic> ||
          decoded['version'] != SkinIndex.version ||
          decoded['items'] is! List ||
          (decoded['items'] as List).length != parsed.length;
    } on FormatException {
      malformed = true;
    }
    final List<SavedSkin> existing = <SavedSkin>[];
    for (final SavedSkin skin in parsed.items) {
      final String? path = pathForFile(skin.file);
      if (path != null && await File(path).exists()) {
        existing.add(skin);
      }
    }

    _index = SkinIndex.empty();
    for (final SavedSkin skin in existing.reversed) {
      _index.add(skin);
    }

    if (malformed || existing.length != parsed.length) {
      await _backupBrokenIndex(source);
      await _writeIndex();
    }
  }

  Future<void> _backupBrokenIndex(String source) async {
    try {
      final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
      await File('${_root.path}/index.corrupt.$stamp.json').writeAsString(source);
    } on FileSystemException catch (error) {
      debugPrint('SkinStore: cannot back up index: $error');
    }
  }

  Future<void> _writeIndex() async {
    final String data = _index.encode();
    final File temp = File('${_indexFile.path}.tmp');
    try {
      await temp.writeAsString(data, flush: true);
      if (await _indexFile.exists()) {
        await _indexFile.delete();
      }
      await temp.rename(_indexFile.path);
    } on FileSystemException catch (error) {
      debugPrint('SkinStore: atomic index write failed, falling back: $error');
      await _indexFile.writeAsString(data, flush: true);
      try {
        if (await temp.exists()) {
          await temp.delete();
        }
      } on FileSystemException catch (cleanupError) {
        debugPrint('SkinStore: cannot remove temp index: $cleanupError');
      }
    }
  }

  Future<SavedSkin> add(
    Uint8List png, {
    required ModelInfo model,
    String? tagId,
  }) async {
    await _galleryDir.create(recursive: true);
    final DateTime now = DateTime.now();
    final String id = '${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}';
    final String fileName = '$id.png';
    await File('${_galleryDir.path}/$fileName').writeAsBytes(png, flush: true);

    final SavedSkin skin = SavedSkin(
      id: id,
      file: fileName,
      modelId: model.id,
      modelName: model.name,
      tagId: tagId,
      createdAt: now,
    );

    final List<SavedSkin> previous = _index.items;
    final List<SavedSkin> pruned = _index.add(skin);
    try {
      await _writeIndex();
    } on Object {
      _index.replaceAll(previous);
      try {
        await File('${_galleryDir.path}/$fileName').delete();
      } on FileSystemException catch (error) {
        debugPrint('SkinStore: cannot remove unindexed image $fileName: $error');
      }
      rethrow;
    }

    for (final SavedSkin old in pruned) {
      final String? path = pathForFile(old.file);
      if (path == null) {
        continue;
      }
      try {
        final File file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException catch (error) {
        debugPrint('SkinStore: cannot prune ${old.file}: $error');
      }
    }
    return skin;
  }

  Future<void> delete(SavedSkin skin) async {
    _index.removeWhere((SavedSkin item) => item.id == skin.id);
    final String? path = pathForFile(skin.file);
    if (path != null) {
      try {
        final File file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException catch (error) {
        debugPrint('SkinStore: cannot delete ${skin.file}: $error');
      }
    }
    await _writeIndex();
  }

  Future<StoredDesign?> loadDesign(String modelId) async {
    final String safeId = _safeName(modelId);
    final File texture = File('${_designDir.path}/$safeId.png');
    if (!await texture.exists()) {
      return null;
    }
    try {
      final Uint8List bytes = await texture.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      String? tagId;
      final File meta = File('${_designDir.path}/$safeId.json');
      if (await meta.exists()) {
        final Object? decoded = jsonDecode(await meta.readAsString());
        if (decoded is Map<String, dynamic> && decoded['tagId'] is String) {
          tagId = decoded['tagId'] as String;
        }
      }
      return StoredDesign(bytes: bytes, tagId: tagId);
    } on FileSystemException catch (error) {
      debugPrint('SkinStore: cannot read design for $modelId: $error');
      return null;
    } on FormatException catch (error) {
      debugPrint('SkinStore: corrupt design metadata for $modelId: $error');
      return null;
    }
  }

  Future<void> saveDesign(
    String modelId,
    Uint8List bytes, {
    String? tagId,
  }) async {
    await _designDir.create(recursive: true);
    final String safeId = _safeName(modelId);
    await File('${_designDir.path}/$safeId.png').writeAsBytes(bytes, flush: true);
    await File('${_designDir.path}/$safeId.json').writeAsString(
      jsonEncode(<String, Object?>{
        'tagId': tagId,
        'savedAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> deleteDesign(String modelId) async {
    final String safeId = _safeName(modelId);
    for (final String extension in <String>['png', 'json']) {
      try {
        final File file = File('${_designDir.path}/$safeId.$extension');
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException catch (error) {
        debugPrint('SkinStore: cannot delete design $safeId.$extension: $error');
      }
    }
  }

  Future<String?> loadLastModelId() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastModelPrefsKey);
    } on Object catch (error) {
      debugPrint('SkinStore: cannot read last model: $error');
      return null;
    }
  }

  Future<void> saveLastModelId(String modelId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastModelPrefsKey, modelId);
    } on Object catch (error) {
      debugPrint('SkinStore: cannot persist last model: $error');
    }
  }

  /// One-time import of the old `my_skins` base64 list into PNG files.
  Future<void> _migrateLegacy() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? legacy = prefs.getStringList(_legacyPrefsKey);
      if (legacy == null || legacy.isEmpty) {
        return;
      }
      final DateTime now = DateTime.now();
      for (int index = 0; index < legacy.length; index++) {
        try {
          final Uint8List bytes = base64Decode(legacy[index]);
          if (bytes.isEmpty) {
            continue;
          }
          final String id = 'legacy_${now.microsecondsSinceEpoch}_$index';
          await File('${_galleryDir.path}/$id.png').writeAsBytes(bytes, flush: true);
          final List<SavedSkin> pruned = _index.add(
            SavedSkin(
              id: id,
              file: '$id.png',
              modelId: 'legacy',
              modelName: 'Импорт',
              tagId: null,
              createdAt: now,
            ),
          );
          for (final SavedSkin old in pruned) {
            final String? path = pathForFile(old.file);
            if (path != null) {
              try {
                final File file = File(path);
                if (await file.exists()) {
                  await file.delete();
                }
              } on FileSystemException catch (error) {
                debugPrint('SkinStore: cannot prune imported skin ${old.file}: $error');
              }
            }
          }
        } on FormatException catch (error) {
          debugPrint('SkinStore: legacy skin $index is not base64: $error');
        } on FileSystemException catch (error) {
          debugPrint('SkinStore: cannot import legacy skin $index: $error');
        }
      }
      await _writeIndex();
      await prefs.remove(_legacyPrefsKey);
    } on Object catch (error) {
      debugPrint('SkinStore: legacy migration skipped: $error');
    }
  }

  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
