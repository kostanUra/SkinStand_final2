import 'dart:convert';

import 'package:flutter/material.dart';

/// One 3D model shipped with the app.
///
/// [bodyEntities] lists the glTF **node names** that make up the weapon body.
/// The `interactive_3d` plugin addresses textures by node/entity name, so every
/// name here must exist in the corresponding GLB file (validated by
/// `test/catalog_test.dart`).
class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.glb,
    required this.bodyEntities,
  });

  final String id;
  final String name;
  final String category;
  final String glb;
  final List<String> bodyEntities;
}

/// Parsed `assets/catalog.json`.
class Catalog {
  const Catalog._(this.models);

  final List<ModelInfo> models;

  static Catalog parse(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('catalog.json is not valid JSON: ${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('catalog.json: root must be a JSON object');
    }
    final Object? rawModels = decoded['models'];
    if (rawModels is! List) {
      throw const FormatException('catalog.json: "models" must be a list');
    }

    final List<ModelInfo> models = <ModelInfo>[];
    final Set<String> ids = <String>{};

    for (final Object? raw in rawModels) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('catalog.json: every model must be an object');
      }
      final String id = _requireString(raw, 'id');
      final String name = _requireString(raw, 'name');
      final String category = _requireString(raw, 'category');
      final String glb = _requireString(raw, 'glb');
      if (!glb.endsWith('.glb')) {
        throw FormatException('catalog.json: $id: "glb" must point to a .glb file');
      }
      final Object? rawEntities = raw['bodyEntities'];
      if (rawEntities is! List) {
        throw FormatException('catalog.json: $id: "bodyEntities" must be a list');
      }
      final List<String> entities = <String>[];
      for (final Object? entity in rawEntities) {
        if (entity is! String || entity.trim().isEmpty) {
          throw FormatException(
            'catalog.json: $id: "bodyEntities" must contain non-empty strings',
          );
        }
        entities.add(entity);
      }
      if (entities.isEmpty) {
        throw FormatException('catalog.json: $id: "bodyEntities" is empty');
      }
      if (!ids.add(id)) {
        throw FormatException('catalog.json: duplicate model id "$id"');
      }
      models.add(
        ModelInfo(
          id: id,
          name: name,
          category: category,
          glb: glb,
          bodyEntities: List<String>.unmodifiable(entities),
        ),
      );
    }

    if (models.isEmpty) {
      throw const FormatException('catalog.json: no models defined');
    }
    return Catalog._(List<ModelInfo>.unmodifiable(models));
  }

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('catalog.json: "$key" must be a non-empty string');
    }
    return value;
  }

  ModelInfo? byId(String? id) {
    if (id == null) {
      return null;
    }
    for (final ModelInfo model in models) {
      if (model.id == id) {
        return model;
      }
    }
    return null;
  }

  List<String> get categories {
    final List<String> result = <String>[];
    for (final ModelInfo model in models) {
      if (!result.contains(model.category)) {
        result.add(model.category);
      }
    }
    return result;
  }

  List<ModelInfo> inCategory(String category) =>
      models.where((ModelInfo model) => model.category == category).toList();
}

/// One visual style that can be applied to a model.
class TagInfo {
  const TagInfo({
    required this.id,
    required this.name,
    required this.texture,
    required this.preview,
    required this.accent,
  });

  final String id;
  final String name;

  /// Square, texture-like image (1024x1024) that is uploaded to the model.
  final String texture;

  /// Catalog artwork for reference (not a texture).
  final String preview;

  final Color accent;
}

/// Parsed `assets/tags/manifest.json`.
class TagCatalog {
  const TagCatalog(this.tags);

  final List<TagInfo> tags;

  static TagCatalog parse(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('tag manifest is not valid JSON: ${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('tag manifest: root must be a JSON object');
    }
    final Object? rawTags = decoded['tags'];
    if (rawTags is! List) {
      throw const FormatException('tag manifest: "tags" must be a list');
    }

    final List<TagInfo> tags = <TagInfo>[];
    final Set<String> ids = <String>{};
    for (final Object? raw in rawTags) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('tag manifest: every tag must be an object');
      }
      final String id = Catalog._requireString(raw, 'id');
      final String name = Catalog._requireString(raw, 'name');
      final String texture = Catalog._requireString(raw, 'texture');
      final String preview = raw['preview'] is String ? raw['preview'] as String : '';
      final Color accent = _parseColor(raw['accent']);
      if (!ids.add(id)) {
        throw FormatException('tag manifest: duplicate tag id "$id"');
      }
      tags.add(
        TagInfo(
          id: id,
          name: name,
          texture: texture,
          preview: preview,
          accent: accent,
        ),
      );
    }
    if (tags.isEmpty) {
      throw const FormatException('tag manifest: no tags defined');
    }
    return TagCatalog(List<TagInfo>.unmodifiable(tags));
  }

  static Color _parseColor(Object? raw) {
    if (raw is! String) {
      return const Color(0xFFFF8A00);
    }
    final String hex = raw.replaceFirst('#', '');
    if (hex.length != 6) {
      return const Color(0xFFFF8A00);
    }
    final int? value = int.tryParse(hex, radix: 16);
    if (value == null) {
      return const Color(0xFFFF8A00);
    }
    return Color(0xFF000000 | value);
  }

  TagInfo? byId(String? id) {
    if (id == null) {
      return null;
    }
    for (final TagInfo tag in tags) {
      if (tag.id == id) {
        return tag;
      }
    }
    return null;
  }
}
