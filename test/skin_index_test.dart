import 'package:flutter_test/flutter_test.dart';
import 'package:skinstand/src/data/skin_index.dart';

void main() {
  test('malformed index data does not crash gallery loading', () {
    expect(SkinIndex.parse('{not json').items, isEmpty);
    expect(SkinIndex.parse('[]').items, isEmpty);
    expect(SkinIndex.parse('{"items":[null,{"id":"bad"}]}').items, isEmpty);
  });

  test('gallery index keeps newest items within its configured cap', () {
    final SkinIndex index = SkinIndex.empty();
    for (int i = 0; i < SkinIndex.maxItems + 2; i++) {
      index.add(
        SavedSkin(
          id: '$i',
          file: '$i.png',
          modelId: 'akr',
          modelName: 'AKR',
          tagId: null,
          createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );
    }

    expect(index.length, SkinIndex.maxItems);
    expect(index.items.first.id, '${SkinIndex.maxItems + 1}');
    expect(index.items.last.id, '2');
  });

  test('gallery metadata rejects file paths', () {
    final SavedSkin? skin = SavedSkin.fromJson(<String, Object>{
      'id': 'unsafe',
      'file': '../outside.png',
      'modelId': 'akr',
      'modelName': 'AKR',
      'createdAt': DateTime.utc(2026).toIso8601String(),
    });

    expect(skin, isNull);
  });
}
