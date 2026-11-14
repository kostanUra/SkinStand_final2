import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skinstand/src/catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog catalog;
  late TagCatalog tags;

  setUpAll(() {
    catalog = Catalog.parse(
      File('assets/catalog.json').readAsStringSync(),
    );
    tags = TagCatalog.parse(
      File('assets/tags/manifest.json').readAsStringSync(),
    );
  });

  test('catalog covers every GLB and every configured entity exists', () {
    final List<FileSystemEntity> glbFiles = Directory('assets')
        .listSync()
        .where((FileSystemEntity file) => file.path.toLowerCase().endsWith('.glb'))
        .toList();
    expect(catalog.models, hasLength(glbFiles.length));

    final Set<String> modelPaths = <String>{};
    for (final ModelInfo model in catalog.models) {
      expect(modelPaths.add(model.glb), isTrue, reason: 'duplicate ${model.glb}');
      final Set<String> nodeNames = _readNodeNames(File(model.glb));
      expect(model.bodyEntities, isNotEmpty, reason: model.id);
      for (final String entity in model.bodyEntities) {
        expect(
          nodeNames,
          contains(entity),
          reason: '${model.id} references missing GLB node "$entity"',
        );
      }
    }
  });

  test('every tag has a texture and a preview asset', () {
    expect(tags.tags, hasLength(24));
    for (final TagInfo tag in tags.tags) {
      expect(File(tag.texture).existsSync(), isTrue, reason: tag.texture);
      expect(File(tag.preview).existsSync(), isTrue, reason: tag.preview);
    }
  });
}

Set<String> _readNodeNames(File file) {
  final Uint8List bytes = file.readAsBytesSync();
  final ByteData data = ByteData.sublistView(bytes);
  expect(data.getUint32(0, Endian.little), 0x46546C67, reason: file.path);
  expect(data.getUint32(4, Endian.little), 2, reason: file.path);
  expect(data.getUint32(8, Endian.little), bytes.length, reason: file.path);

  int offset = 12;
  while (offset + 8 <= bytes.length) {
    final int chunkLength = data.getUint32(offset, Endian.little);
    final int chunkType = data.getUint32(offset + 4, Endian.little);
    final int chunkStart = offset + 8;
    final int chunkEnd = chunkStart + chunkLength;
    if (chunkEnd > bytes.length) {
      throw FormatException('${file.path}: truncated GLB chunk');
    }
    if (chunkType == 0x4E4F534A) {
      final Object? decoded = jsonDecode(
        utf8.decode(bytes.sublist(chunkStart, chunkEnd)).trimRight(),
      );
      if (decoded is! Map<String, dynamic> || decoded['nodes'] is! List) {
        throw FormatException('${file.path}: missing glTF node table');
      }
      return <String>{
        for (final Object? node in decoded['nodes'] as List<Object?>)
          if (node is Map<String, dynamic> && node['name'] is String)
            node['name'] as String,
      };
    }
    offset = chunkEnd;
  }
  throw FormatException('${file.path}: missing glTF JSON chunk');
}
