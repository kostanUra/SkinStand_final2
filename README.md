# SkinStand

Flutter app for applying skin textures to the bundled 3D models and saving model previews to a local gallery.

## Requirements

- Flutter 3.44.0 or newer (Dart 3.6 or newer)
- Android toolchain for device builds

## Run and validate

```shell
flutter pub get
flutter analyze
flutter test
flutter run
```

The Android Codemagic workflow generates the Android platform project before building. Model and tag metadata live in `assets/catalog.json` and `assets/tags/manifest.json`; their entity names and referenced files are checked by `flutter test`.

The original images under `assets/tags/` are previews. The square, generated base-color textures used by the editor are under `assets/textures/`. To regenerate the catalog or textures, use the scripts in `tool/`; texture generation requires Python with NumPy and Pillow.

Gallery screenshots are stored as PNG files in application documents, with a bounded JSON index. The editor restores each model's last applied texture. 3D screenshot publishing is disabled on iOS because the renderer uses a native platform view that Flutter's repaint-boundary capture cannot reliably include.
