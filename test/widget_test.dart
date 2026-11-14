import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skinstand/main.dart';

void main() {
  testWidgets('app starts with the SkinStand title', (WidgetTester tester) async {
    await tester.pumpWidget(const SkinStandApp());

    final MaterialApp app = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(app.title, '3D Skin Creator');
  });
}
