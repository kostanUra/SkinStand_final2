import 'dart:convert';

/// One published skin, as stored in `index.json`.
class SavedSkin {
  const SavedSkin({
    required this.id,
    required this.file,
    required this.modelId,
    required this.modelName,
    required this.tagId,
    required this.createdAt,
  });

  final String id;

  /// File name inside the gallery directory (never a path).
  final String file;

  final String modelId;
  final String modelName;
  final String? tagId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'file': file,
        'modelId': modelId,
        'modelName': modelName,
        if (tagId != null) 'tagId': tagId,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Returns null instead of throwing for malformed entries: a single bad
  /// record must not destroy the whole gallery.
  static SavedSkin? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    final Object? id = raw['id'];
    final Object? file = raw['file'];
    final Object? modelId = raw['modelId'];
    final Object? modelName = raw['modelName'];
    final Object? tagId = raw['tagId'];
    final Object? createdAt = raw['createdAt'];

    if (id is! String || id.isEmpty) {
      return null;
    }
    if (file is! String || file.isEmpty || file.contains('/') || file.contains('\\')) {
      return null;
    }
    if (modelId is! String || modelId.isEmpty) {
      return null;
    }
    if (modelName is! String || modelName.isEmpty) {
      return null;
    }
    if (tagId != null && tagId is! String) {
      return null;
    }
    final DateTime? parsed = createdAt is String ? DateTime.tryParse(createdAt) : null;

    return SavedSkin(
      id: id,
      file: file,
      modelId: modelId,
      modelName: modelName,
      tagId: tagId is String ? tagId : null,
      createdAt: parsed ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Pure, file-system independent gallery index.
///
/// Kept separate from [SkinStore] so ordering, pruning and corruption handling
/// can be unit-tested without plugins.
class SkinIndex {
  SkinIndex._(this._items);

  factory SkinIndex.empty() => SkinIndex._(<SavedSkin>[]);

  /// Upper bound of stored skins; oldest entries are pruned.
  static const int maxItems = 120;

  static const String version = '1';

  final List<SavedSkin> _items;

  List<SavedSkin> get items => List<SavedSkin>.unmodifiable(_items);

  int get length => _items.length;

  /// Never throws: malformed input yields an empty index and the store backs up
  /// the broken file before rewriting it.
  static SkinIndex parse(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return SkinIndex.empty();
    }
    if (decoded is! Map<String, dynamic>) {
      return SkinIndex.empty();
    }
    final Object? rawItems = decoded['items'];
    if (rawItems is! List) {
      return SkinIndex.empty();
    }
    final List<SavedSkin> items = <SavedSkin>[];
    for (final Object? raw in rawItems) {
      final SavedSkin? skin = SavedSkin.fromJson(raw);
      if (skin != null) {
        items.add(skin);
      }
    }
    return SkinIndex._(items);
  }

  String encode() => jsonEncode(<String, dynamic>{
        'version': version,
        'items': <Map<String, dynamic>>[
          for (final SavedSkin skin in _items) skin.toJson(),
        ],
      });

  /// Inserts [item] at the top and returns the entries that fell off the cap.
  List<SavedSkin> add(SavedSkin item) {
    _items.insert(0, item);
    final List<SavedSkin> removed = <SavedSkin>[];
    while (_items.length > maxItems) {
      removed.add(_items.removeLast());
    }
    return removed;
  }

  int removeWhere(bool Function(SavedSkin skin) test) {
    final int before = _items.length;
    _items.removeWhere(test);
    return before - _items.length;
  }

  bool contains(String id) =>
      _items.any((SavedSkin skin) => skin.id == id);

  void replaceAll(Iterable<SavedSkin> items) {
    _items
      ..clear()
      ..addAll(items);
    while (_items.length > maxItems) {
      _items.removeLast();
    }
  }
}
