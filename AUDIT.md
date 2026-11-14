# SkinStand — Deep Project Audit

**Project:** `skinstand` — Flutter "3D Skin Creator" (`version: 1.0.0+1`)
**Audited:** 2026-11-14
**Audited revision:** `918fd40` (the `HEAD` revision at audit time)
**Audit scope:** the tracked files at the audited revision: `lib/main.dart` (471 lines), `pubspec.yaml`, `codemagic.yaml`, all 46 `.glb` models, all 24 `assets/tags/*.jpg`, git history, and the `interactive_3d` plugin API/source used by the app. This report does not assess uncommitted working-tree changes.
**Environment note:** no Flutter/Dart SDK is installed on this machine (`flutter`/`dart` not on PATH, no pub cache), so no `pub get`, `analyze`, or device build was run. All findings below come from static code review plus binary/asset-level verification (scripts parsing the GLB headers, JSON chunks, accessors, node/material tables, embedded textures) and from the plugin's published docs/source. Claims that need a device to confirm are explicitly marked **[verify on device]**.

**Severity key:** P0 = core workflow blocked or data at immediate risk; P1 = major reliability, release, or usability gap; P2 = lower-impact robustness, accessibility, legal, or polish concern. These are product priorities, not vulnerability severity ratings.

**Coverage limits:** this is a static product/code audit, not a penetration test or legal opinion. No dependency vulnerability scan, secret scan, platform-native source review, runtime test, or third-party asset-rights verification was performed. Quantitative GLB and image checks used one-off scripts that are not included in the audited revision, so those checks are not directly reproducible from that revision.

---

## 0. TL;DR

The app looks finished, but its **core loop (pick a model → apply a tag/brush → publish) cannot work** for three independent reasons, and the app **reports success anyway**:

| # | Blocking defect | Effect |
|---|---|---|
| 1 | `setEntityTexture(name: 'Material', …)` | **No model contains an entity or material named `Material`** (0/46). The call silently does nothing. |
| 2 | The "tag" JPEGs are **catalog preview renders** (a small picture of a gun on a dark UI background, 1280×591), not texture atlases | Even with the right entity name, the gun would be covered by a shrunken photo of a different gun plus a "НАЗАД" button. |
| 3 | No load gating, and the plugin **silently returns** when the renderer isn't ready | Tapping `ТЕГ` before/while a model loads does nothing, while a green "Тег применен!" snackbar is shown. |

Secondary blockers: publishing stores multi-MB base64 PNGs in `SharedPreferences` with no delete/cap (data-loss / ANR risk), the layout overflows as soon as the keyboard opens, and iOS screenshot capture is architecturally impossible with the current widget tree.

**Counts:** 4 × P0, 13 × P1, and 8 × P2 (25 indexed findings total), plus a product-gap list. Details and fixes below.

---

## 1. What the project actually is (verified facts)

- **At the audited revision:** 3 tracked application/config source files (`lib/main.dart`, `pubspec.yaml`, `codemagic.yaml`), 73 tracked files total, ~11 MB of git objects.
- **No platform folders** (`android/`, `ios/`), no `.gitignore`, no `README`, no `LICENSE`, no `test/`, no `analysis_options.yaml`, no `dev_dependencies`.
- **46 GLB models**, 17.2 MB total. Names are CS:GO-style rips (`Gunlock1`, `Stattrack`, `Sticker1Mtrl`, `InspectAKR`, …), each with an embedded flat base-color atlas (512×512 or 1024×1024).
- **24 tag JPEGs**, 1.1 MB total, all exactly **1280×591**, all screenshots of a skin-store UI (title, rarity, collection badge, "НАЗАД" button) — see §4.2.
- Android-only CI (`flutter create . --platforms=android` + `flutter build apk --debug`), no signing, no tests, no analyze step.
- `interactive_3d: ^2.2.0` — resolves to **2.5.0** today (Dart `^3.6.0`, Flutter `>=3.44.0`). On Android the plugin renders through Flutter's `Texture` API; on iOS through a `UiKitView` platform view.

---

## 2. How this was verified

1. **GLB structural validation** — magic/version/declared-length vs. file size, chunk walk, JSON parse, trailing bytes. Result: **all 46 files are structurally valid**, no duplicates, no truncation.
2. **Node/material/UV inventory** — parsed every node, mesh, primitive, material and `TEXCOORD_0` range; extracted embedded textures and inspected them visually.
3. **Tag asset inspection** — dimensions and visual content of all 24 JPEGs.
4. **Plugin contract** — read `interactive_3d` 2.5.0 `widget.dart`, `controller.dart`, `models.dart`, `CHANGELOG.md`, README, and Android `build.gradle`. Confirmed: `EntityTexture.name` is documented as *"Entity node name in the glTF/GLB"*; the native call is a **no-op when the renderer/texture isn't created yet** (`if (_platform == null || _textureId == null) return;`).
5. **Git history** — the `'Material'` name has been wrong since the first commit (`3eb3c2c`); previous comments even guessed `'DefaultMaterial'`, which is a **material** name, not an **entity** name, so it would also fail.

---

## 3. Findings index

| ID | Sev | Area | Finding |
|---|---|---|---|
| SB-01 | **P0** | Tag/brush | Texture target `'Material'` exists in 0/46 models → core feature dead |
| SB-02 | **P0** | Assets | Tag JPEGs are UI preview renders, not texture atlases (and are weapon-specific) |
| SB-03 | **P0** | Feedback | False success: no load gating, plugin no-ops silently, green snackbar always |
| SB-04 | **P0** | Gallery | Publish stores base64 PNGs in SharedPreferences, unbounded, no delete → data bloat/ANR/OOM |
| SB-05 | P1 | Gallery | Screenshot not gated on load; errors swallowed; `byteData!` can throw; iOS platform view un-capturable |
| SB-06 | P1 | Versions | `^2.2.0` allows 2.2.0–2.3.0, whose known texture/model-switch crash is fixed only in 2.4.0 |
| SB-07 | P1 | Loading | No `onModelLoaded` / `onModelLoadError` / `errorBuilder` / `loadingWidget` → black screen, no retry |
| SB-08 | P1 | State | Applied skin is ephemeral: switching model or restarting loses it; no reset, no re-edit |
| SB-09 | P1 | Layout | Bottom panel is not scrollable → `RenderFlex overflow` when keyboard opens; no bottom `SafeArea` |
| SB-10 | P1 | Brush | Drawing pad: portrait canvas vs. 2.17:1 atlas, white bg, pixelRatio 1.0, no UV guide, tap dots lost, O(n) repaint |
| SB-11 | P1 | Brush | `Navigator.pop` after `await` without `mounted`; unawaited `setEntityTexture`; controller `StateError` uncaught |
| SB-12 | P1 | UX | Tag hint advertises non-existent tags (`fire`, `neon`); no tag list/preview; `posion.jpg` typo; wrong error text |
| SB-13 | P1 | Errors | Every failure path is `debugPrint` only; invalid prefs data crashes the gallery build |
| SB-14 | P1 | Quality | Zero tests, no lints, no analyze/CI checks; generated `analysis_options.yaml` would break analyze |
| SB-15 | P1 | CI/Build | Debug-only APK, `com.example.skinstand` applicationId, no signing, wrong runner, no cache, no ABI split |
| SB-16 | P1 | Repo | No android/ios/.gitignore/README → no persistent platform config, no reproducibility |
| SB-17 | P1 | Structure | 471-line god-file; model list duplicated from filesystem; no manifest for entity targets |
| SB-18 | P2 | Gallery | Full-res `base64Decode` per build, no `cacheWidth`, no open/share/delete |
| SB-19 | P2 | A11y/i18n | Icon buttons without tooltips/semantics; hardcoded Russian; no localization |
| SB-20 | P2 | Code | `imageData.buffer.asUint8List()` ignores view offset/length |
| SB-21 | P2 | Code | `TextEditingController` never disposed; `Offset.zero` sentinel; `shouldRepaint => true` |
| SB-22 | P2 | Cosmetic | Unused white container under a black background; square gallery tiles letterbox portraits |
| SB-23 | P2 | Legal | Ships Valve/CS:GO assets and store renders → publishing risk |
| SB-24 | P2 | Assets | Embedded UI leftovers (`bg_button_yellow`), a magenta/UV-test-looking flash atlas |
| SB-25 | P2 | Robustness | No `PopScope` / unsaved-changes confirmation; no state restoration for model selection |

---

## 4. P0 — the core feature is broken

### 4.1 SB-01 — `setEntityTexture(name: 'Material')` targets something that does not exist

`lib/main.dart:126` and `lib/main.dart:148` both do:

```dart
await _controller.setEntityTexture(name: 'Material', bytes: bytes);
```

The plugin's `EntityTexture` is documented as **"Entity node name in the glTF/GLB"** (`models.dart`), and the README's usage example applies it to *parts* (`'Teeth_Upper_8'`), i.e. the names you get from `onSelectionChanged`. For these models the entity names are glTF **node** names.

I scanned all 46 GLBs. Result:

- Models containing a node named `Material`: **0 / 46**
- Models containing a *material* named `Material`: **0 / 46**
- Material names that do exist: `DefaultMaterial`, `DefaultMaterial.001/.003`, `Gun`, `Gun.001…Gun.011`, `Default-Material`, `Default-Material.001/.002`, `Molotov_PBR`, `Stattrack`, `Sticker1Mtrl…Sticker4Mtrl`
- Body entity names are **different on almost every model**: `Gunlock1`/`Magazine1`/`LOD_Template` for most rifles, `Butterfly` for the butterfly knife, `Karambit_1`, `L0_LOD0_16`, `Stiletto`, `Tanto_1`, `Jagdkommando_LOD0`, `SubMesh_0`, `LOD0_Mono`/`LOD0_Mono.001`, `Gunlock1.001`/`LOD_Template.001` for newer models, etc.

So every tag and every brush stroke is a **silent no-op** on every one of the 46 models. The in-code comment ("если теги не применяются, значит материал… называется не 'Material'") is on the wrong axis: it's not a material name at all, and no single constant can work across the catalogue.

**Even the suggested alternatives fail.** `'DefaultMaterial'` is a material, not an entity — and on models like `butterfly`, `karambit`, `flash`, `molotov`, `mantis` there isn't even a node with that material.

**Fix:** ship/generate a per-model entity map and use `setEntityTextures` with all body parts at once. Appendix A is a ready-to-use map computed from the 46 files (body meshes only; stickers, StatTrak, sights/lenses, cartridges and bullets excluded). Also log the *runtime* names once via `onSelectionChanged`, because the plugin warns names can differ between Android and iOS ("Names match those in `onSelectionChanged` **on the same platform**").

**Caveat that makes this urgent:** the plugin's early-return means a wrong name produces no error, no log, no visual change — just the green success snackbar (SB-03).

---

### 4.2 SB-02 — the "tags" are preview renders, not textures

All 24 files in `assets/tags/` are 1280×591 screenshots of a skin-store page: a small rendered gun on a dark gradient, with a collection badge, a weapon/skin title ("M4 \"TIGER\"", "AKR \"DIGITAL BURST\""), a rarity label, and a literal **"НАЗАД"** button (see `assets/tags/carbon.jpg`, `assets/tags/tiger.jpg`, `assets/tags/samurai.jpg`).

The models' base color maps are flat UV atlases: 512×512 for the AKR/M4 family (I extracted `akr.glb`'s: a black/grey atlas with "KILL COUNTER" and digit strips) and 1024×1024 for `flash.glb` (a magenta UV-test-looking layout). On every model at least one mesh spans >90 % of the 0…1 UV range in both axes, while secondary body meshes sample sub-rectangles of the same atlas (e.g. `m4a1`'s `Gunlock1` uses u≈0.41–0.79, `LOD_Template` uses the full range).

Consequences, independent of SB-01:

1. Mapping a 1280×591 **picture of a whole gun** across a **UV atlas** means each polygon samples an arbitrary pixel of that picture. The result is noise, dark background and UI text smeared over the weapon — not a skin.
2. The 2.166:1 aspect is resampled onto a 1:1 UV space, adding horizontal distortion.
3. Each tag is authored for a specific weapon (`G22 "CARBON"`, `M4 "TIGER"`, `AKR "DIGITAL BURST"`), but the UI applies **any** tag to **any** of the 46 selected models. An M4 atlas on a knife is meaningless even with perfect assets.

**Fix:** separate two asset classes:

- **Catalog previews** — keep these 1280×591 renders for a browsable tag grid (they're fine for that, once you crop off the "НАЗАД" chrome).
- **Texture sources** — ship actual flat skin atlases (1024×1024 PNG with the same UV layout as the model, or seamless tileable patterns such as carbon/hex/stripes that can be tiled in UV space) under a separate folder with a JSON manifest `{id, displayName, atlasPath, previewPath, compatibleModels}`.

Caveat: the models appear to be CS:GO rips, so their UV layout matches Valve's weapon atlases; a "tag" only looks right if it is the corresponding atlas, not a render. Also note SB-23.

---

### 4.3 SB-03 — the app lies about success (and drops input while loading)

Two independent silent paths, both ending in a green snackbar at `lib/main.dart:129-132`:

1. **Wrong name** (SB-01): plugin does nothing.
2. **Renderer not ready:** on Android, `Interactive3dState.setEntityTextures` starts with `if (_platform == null || _textureId == null) return;`. The widget exposes `onModelLoaded` and documents: *"controller calls made earlier are ignored or have no effect."* This app never subscribes to it. Because the textures are only created inside `LayoutBuilder` → `_initializeTexture` → async platform calls, there is a real window after startup, after `runApp`, and after every dropdown model switch (`ValueKey(_currentModel)` at `lib/main.dart:206` creates a brand-new `Interactive3dState`) during which taps are lost. The user still gets "Тег применен!".

3. Bonus: `applyTag` awaits `rootBundle.load` (a few hundred KB), then calls the controller; if the user changes the model in that gap, the texture is applied to the new model (or nowhere). No `_modelReady` flag, no generation token.

**Fix sketch:**

```dart
bool _modelReady = false;

Interactive3d(
  key: ValueKey(_currentModel),
  controller: _controller,
  modelPath: _currentModel,
  onModelLoaded: () => setState(() => _modelReady = true),
  onModelLoadError: (e, st) => setState(() { _modelReady = false; _loadError = e; }),
  errorBuilder: (c, e) => _LoadError(onRetry: () => setState(() => _modelKey++)),
  loadingWidget: const Center(child: CircularProgressIndicator()),
)

// disable while not ready
onPressed: _modelReady ? _applyTag : null

Future<void> _applyTag() async {
  final bytes = await _loadTagBytes(_tagController.text);
  if (bytes == null) { _toast('Тег не найден', error: true); return; }
  final names = kBodyEntities[_currentModel] ?? const <String>[];
  if (names.isEmpty) { _toast('Для этой модели тег не настроен', error: true); return; }
  try {
    await _controller.setEntityTextures(
      [for (final n in names) EntityTexture(name: n, bytes: bytes)],
    );
    if (!mounted) return;
    _toast('Тег применён');
  } on Object catch (e) {          // and catch the platform channel errors
    if (!mounted) return;
    _toast('Не удалось применить тег: $e', error: true);
  }
}
```

Note the plugin's controller throws `StateError('Interactive3dController is not attached to a widget')` if the widget was disposed mid-await (possible when switching models), so the `try` is mandatory, not optional.

---

### 4.4 SB-04 — publishing writes multi-MB base64 images into `SharedPreferences`

`lib/main.dart:154-178`:

```dart
final image = await boundary.toImage(pixelRatio: 2.0);        // e.g. 786×2400
final bytes = byteData!.buffer.asUint8List();                 // PNG, MBs
String base64Image = base64Encode(bytes);                     // +33 %
savedSkins.add(base64Image);
await prefs.setStringList('my_skins', savedSkins);
```

Problems:

- **Wrong storage class.** `SharedPreferences` is an XML key-value cache read into memory; it's not a blob store. Every save re-serialises the **entire** list (all previous skins included) and writes it on the platform's queued-work thread; every startup loads the whole XML. At `pixelRatio: 2.0` a portrait 3D panel produces roughly **1.5–4 MB of PNG → 2–5 MB of base64 per skin**. Five skins is a 10–25 MB prefs file. Expect multi-second freezes, `QueuedWork` ANR on Android when the activity pauses, and eventually OOM / prefs corruption. The failure is silent because of SB-13.
- **No delete, no cap, no dedupe.** A user who taps the publish button twice saves the identical skin twice; there is no way to remove anything. Storage only grows.
- **No metadata** — no model, tag, date, or title, so the gallery is just a wall of images and skins can't be reopened for editing.
- **No error handling** — `prefs.setStringList` result is ignored (it returns `bool`), and the `catch` at `:175` only `debugPrint`s, so a failed save produces *nothing* while a successful one produces a snackbar.

**Fix:** store PNG files in the app documents directory (or `getApplicationSupportDirectory`) and keep a small JSON index:

```
<docs>/skins/<uuid>.png          // image only
<docs>/skins/index.json          // [{id, model, tag, createdAt, name}]
```

Use `path_provider` + `dart:io`, cap `pixelRatio` so the longest side is ≤ 1600 px, show a progress indicator while encoding (PNG encoding of a large boundary is not instant), and rebuild the gallery from the directory with `Image.file(..., cacheWidth: 400)`.

---

## 5. P1 findings

### SB-05 — Gallery screenshot: no gating, errors invisible, iOS cannot work

- `publishSkin` (`:157`) force-unwraps `_repaintKey.currentContext!` and `byteData!`; if either is null the app throws into a `catch` that only prints.
- It does **not** check `_modelReady`, so tapping publish during the loading overlay saves a picture of a spinner/black panel.
- On **iOS** the plugin renders through `UiKitView` (`_buildIOSPlatformView`), a platform view. Platform views are not part of Flutter's layer tree rasterisation, so `RenderRepaintBoundary.toImage` **cannot capture the 3D content** — you get the container background only. The app is written as if cross-platform (`MyApp`, `Platform`-agnostic code) but the gallery silently produces blank cards there. **[verify on device]**
- On **Android** the plugin uses the `Texture` API, which is snapshot-able, so capture should work — but it is still worth a device test with Impeller. **[verify on device]**
- `pixelRatio: 2.0` is hardcoded and can massively overshoot on tablets.

**Fix:** gate on `_modelReady`, wrap in a `try` that surfaces a snackbar with the actual error, compute the ratio from `MediaQuery.devicePixelRatio` and a max-dimension clamp, and on iOS hide/omit the 3D view from the capture (or use a native snapshot path) — do not ship a capture path that is guaranteed blank.

### SB-06 — the dependency constraint allows the versions with the crash this app triggers

`pubspec.yaml:12` — `interactive_3d: ^2.2.0` allows 2.2.0, 2.3.0, 2.4.0, 2.5.0. The 2.4.0 changelog says, verbatim:

> Android crash fixes: **no more crash when a view closes, reopens, or resets while a part shows a material override or texture**, when a view closes during or right after loading…

This app does exactly that: the dropdown rebuilds `Interactive3d` with a new `ValueKey` on **every** model change, while a texture may be active. A frozen `pubspec.lock`/resolution on 2.2.0–2.3.0 reproduces that crash. Also, the plugin needs **Dart `^3.6.0`, Flutter `>=3.44.0`**, but the app declares only `sdk: '>=3.0.0 <4.0.0'` and no `flutter:` constraint, so older SDKs fail with a confusing resolver error.

**Fix:** `interactive_3d: ^2.5.0`, add `environment: sdk: ^3.6.0` and `flutter: '>=3.44.0'`, and commit `pubspec.lock` for apps (CI resolves fresh today → non-reproducible builds).

### SB-07 — model load failures are invisible

`Interactive3d` supports `loadingWidget`, `errorBuilder`, `onModelLoaded`, `onModelLoadError`; none are used. On failure (`_loadPhase = failed` with no `errorBuilder`) the plugin removes the overlay and shows an empty black area. The user sees a black rectangle, no message, no retry. This also means a corrupt/unsupported GLB (or a future asset path typo in the hardcoded list) is unreproducible from the field.

### SB-08 — the authored skin is ephemeral

The plugin does not persist textures/overrides ("Keep them in your own state"). This app keeps none, so:

- switching the dropdown loses the applied tag/brush (reloading the model re-applies the original atlas),
- nothing is restored on restart — the only artifact is a screenshot,
- there is no `resetEntityTexture`/`resetAllEntityTextures` in the UI, so there is no way to remove a mis-applied skin other than cycling the model,
- there is no "re-edit from gallery".

**Fix:** keep a per-model design state (`{targets, textureBytes}`), restore it with `initialEntityTextures` on load, persist the bytes to a file, and expose "Сбросить скин".

### SB-09 — layout overflows with the keyboard, and the CTA sits under the system bar

`lib/main.dart:197-296`: `Scaffold(body: Column(children: [Expanded(flex: 3, …), Container(…panel…)]))`. The panel is unconstrained and not scrollable. With `resizeToAvoidBottomInset: true` (default), focusing the tag `TextField` on a landscape phone (≈360 dp tall) leaves roughly `360 − 56 (appbar) − ~200 (panel) − ~230 (keyboard) < 0` → `RenderFlex overflowed` stripes, and the publish button is clipped. On portrait phones with large key heights the same happens.

Independently, the panel has no `SafeArea`/bottom padding, so on gesture-navigation devices the "ВЫЛОЖИТЬ В ГАЛЕРЕЮ" button can be partly under the home indicator.

**Fix:** wrap the panel in `SingleChildScrollView` (or make it a `DraggableScrollableSheet`), add `SafeArea(top: false)`, and/or `resizeToAvoidBottomInset: false` with a `MediaQuery.viewInsets`-aware padding. Test in landscape and with a 3-line font scale.

### SB-10 — the drawing pad cannot produce a usable skin texture

`DrawingPad` (`:355-448`) captures the whole portrait canvas and feeds it to `setEntityTexture`. Against the model's UV atlas:

- **Aspect mismatch** — canvas is roughly 9:16, the atlas is 1:1 (512²/1024²), body UVs span 0…1. Strokes map unpredictably across the weapon's UV islands.
- **Capture at `pixelRatio: 1.0`** (`:371`) → e.g. 400×600 texture for a 2048 px upload slot; blurry after stretching.
- **White background** (`:398`) instead of transparent or a UV template — the white becomes paint over the whole body.
- **No UV guide/template** — the user draws on a blank page and has no idea which stroke lands on the barrel vs. the magazine. This is the product's biggest usability gap.
- **Tap dots are lost** — only `onPanUpdate` adds points; a tap produces no `onPanDown` point, so dots are impossible.
- **`Offset.zero` sentinel** (`:406`, `:463`) — a stroke that legitimately passes through the top-left logical origin (0,0) would be treated as a pen-up; and the painter draws nothing for a one-point stroke.
- **`_points` grows without bound**, and `shouldRepaint => true` (`:470`) rebuilds/repaints the entire trail on every pointer event → O(n²) over a long session.
- **No undo/redo/eraser/brush size** — only "clear everything" and 5 fixed colours. One mistake = start over.

**Fix:** draw on a canvas sized/laid out to the model's UV atlas (1:1, e.g. 1024×1024) with the atlas faintly visible as a guide; capture at `pixelRatio = devicePixelRatio` (clamped); store strokes as `List<Stroke>` (points + colour + width) so undo is cheap and repaint is O(visible strokes); add `onPanDown` for dots.

### SB-11 — async/lifecycle hazards in the drawing flow

- `_saveDrawing` calls `await boundary.toImage(...)`, then `Navigator.pop(context)` (`:376`) with no `mounted` check → "Looking up a deactivated widget's ancestor" if the route was popped during the await (`use_build_context_synchronously`).
- `openBrush`'s `onSave` (`:146-149`) calls `_controller.setEntityTexture(...)` **without `await` and without `catch`** → an unhandled async error, and the user gets no confirmation when returning to the editor. The user returns to the creator with no idea whether the drawing was applied.
- No unsaved-work confirmation when backing out of the pad (SB-25).

### SB-12 — tag entry UX is a guessing game

- Hint text says `'Тег (fire, neon)...'` (`:256`) but **neither `fire` nor `neon` exists** in `assets/tags/`. The 24 real names are carbon, chameleon, daybreak, digital burst, dust devil, fury, geometric, haunt, hunter, lich, monster, nebula, necromancer, noxious, posion, radiation, samurai, scratch, sport v2, stone cold, thorn, tiger, venom, winter sport.
- There is no list, no autocomplete, no thumbnails — even though every tag has a JPEG that would make a perfect picker.
- Only `.jpg` then `.png` are tried; naming is case-normalised but not space/hyphen-normalised.
- The error text always says `assets/tags/$cleanTag.jpg не найден!` (`:136`) even when the `.png` fallback was attempted; and the double `catch (e)` silently swallows the reason (e.g. asset manifest problem).
- `posion.jpg` is a typo of "poison"; renaming it will silently break users who typed "posion".
- `applyTag` doesn't clear the field or dismiss the keyboard, and the keyboard has no `onSubmitted` handler.

### SB-13 — every failure path is invisible

`debugPrint` at `:176` and `:379` is the entire error strategy. Add: gallery `base64Decode(_skins[index])` inside `build` (`:346`) throws on any corrupted value → red error screen, with no recovery path or "clear gallery" action. `Image.memory` has no `errorBuilder`. `prefs` write failures are ignored. There is no `FlutterError.onError`, no `PlatformDispatcher.instance.onError`, no crash reporting, no log export. For a mobile app whose only output is a saved image, this is the difference between "bug report" and "silent data loss".

### SB-14 — no tests, no lints, no CI gates

- No `test/`, no `flutter_test`, no `flutter_lints`, no `analysis_options.yaml`, no `flutter analyze`/`flutter test` in `codemagic.yaml`.
- The 46-model list, tag resolution, and publish path are pure-enough logic that widget/unit tests are trivial and would have caught SB-01 at review time (assert that every entity name in the map exists in the corresponding GLB).
- Latent trap: `flutter create .` in CI **creates** `analysis_options.yaml` with `include: package:flutter_lints/flutter.yaml`, but `flutter_lints` is not a dev dependency. The moment anyone adds `flutter analyze` to CI it fails with "Target of URI doesn't exist". `flutter create` also creates `test/widget_test.dart` referencing a counter that doesn't exist → `flutter test` fails.

### SB-15 — CI builds the wrong artifact

`codemagic.yaml`:

```yaml
instance_type: mac_mini_m2     # Android build on a macOS M2 runner
flutter: stable                # unpinned
flutter create . --project-name=skinstand --platforms=android   # default org → com.example.skinstand
flutter build apk --debug      # debug only
artifacts: build/app/outputs/flutter-apk/*.apk
```

Issues: debug build (JIT, asserts, no tree-shaking → poor 3D performance and huge APK), `com.example.skinstand` applicationId (Play Store rejects `com.example.*`), no signing config, no `--split-per-abi` despite **17.2 MB of assets + Filament native libraries for 4 ABIs** (fat APK will be very large), no Gradle/pub caching, no version bump (`1.0.0+1` forever), no tests, `max_build_duration: 60` is tight for a cold Gradle/NDK/Filament download, and Android builds on macOS runners are slow/expensive for no benefit. Also: the plugin requires **minSdk 24**; the generated project's default `minSdk` depends on the Flutter version, so this should be pinned explicitly in `android/app/build.gradle.kts`.

Also `abiFilters` in the plugin still lists `x86`; verify Filament 1.68 actually ships 32-bit x86 — if not, use `--target-platform android-arm64` or `--split-per-abi` and test on a real arm64 device. **[verify on device]**

### SB-16 — no platform project, no `.gitignore`

The repo contains only `lib/`, `assets/`, `pubspec.yaml`, `codemagic.yaml`. Consequences:

- Every build regenerates the Android project from scratch → applicationId, minSdk, permissions, ProGuard, splash/icon, network-security config, and gradle.properties tweaks can never be persistent.
- No `.gitignore` → the first local `flutter create`/`flutter run` pollutes the working tree with `.dart_tool/`, `build/`, `android/.gradle/`, `*.iml`, `local.properties` (which contains an absolute SDK path).
- No README → a new contributor cannot know that `flutter create .` is required, which tags exist, or which entity names matter.

### SB-17 — one god-file with a model list that duplicates the filesystem

`lib/main.dart` holds app, screen, brush, painter, gallery, and the 46-path asset list. The list is a manual copy of `assets/*.glb` (currently exactly in sync — I verified all 46 entries exist and nothing on disk is missing, but nothing enforces it). Adding a model requires editing Dart; a missing file produces a black panel (SB-07). The mapping "model → texturable entities" doesn't exist at all (SB-01), so there's no place to put the per-model knowledge the feature needs.

**Fix:** split into `src/models/`, `src/services/skin_repository.dart`, `src/screens/`, `src/widgets/`; generate a `assets/catalog.json` (`id`, `name`, `category`, `glb`, `bodyEntities`) at build time from the GLB node tables; drive the dropdown from it.

---

## 6. P2 findings

- **SB-18 — Gallery performance/features.** `base64Decode` runs inside `itemBuilder` on every rebuild; no `cacheWidth`/`cacheHeight`, so each 800×2400 PNG is decoded at full resolution for a 180 dp tile. No delete, share, rename, open, or "use as base". Grid is `childAspectRatio: 1.0` while screenshots are portrait → heavy letterboxing.
- **SB-19 — Accessibility & localization.** Icon-only `IconButton`s (`photo_library`, `brush`, `save`, `clear`) have no `tooltip`, so TalkBack announces nothing. All strings are hardcoded Russian, `MaterialApp.title` is English, no `flutter_localizations`, no `intl`. Font-scale > 1.3 will worsen SB-09.
- **SB-20 — `ByteData` slicing.** `imageData.buffer.asUint8List()` (`:122`) ignores `offsetInBytes`/`lengthInBytes`; should be `asUint8List(imageData.offsetInBytes, imageData.lengthInBytes)`. Today `rootBundle` returns exact views so it works, but it's a latent corruption bug.
- **SB-21 — small code hygiene.** `_tagController` is never disposed; `_points` uses `Offset.zero` as a protocol token; `SignaturePainter.shouldRepaint` always returns true; `DrawingPad.onSave` is a bare `Function(Uint8List)` instead of `ValueChanged<Uint8List>`; `runApp` without `WidgetsFlutterBinding.ensureInitialized()` (harmless today, fragile if plugins are touched before `runApp`).
- **SB-22 — cosmetic dead code / theme drift.** `Container(color: Colors.white)` (`:204`) is fully covered by the plugin's own black background, so it does nothing; comments mix Russian and English; colours are hardcoded in six places instead of a `ColorScheme`.
- **SB-23 — IP/licensing.** The models are recognisably Valve/CS:GO weapon models (node names `InspectAKR`, `Stattrack`, `Sticker1Mtrl`, `Gunlock`), and the tag JPEGs are captures of a skin-market UI including another site's branding. Publishing this on Play/App Store as-is carries a real takedown risk. Needs either licensed/original models or a clear non-commercial stance.
- **SB-24 — asset quality leftovers.** Each GLB embeds a 4×92 `bg_button_yellow` UI image (leftover from the rip), and `flash.glb`'s 1024² base color looks like a magenta UV test map. Harmless but indicates no asset pipeline/validation.
- **SB-25 — no lifecycle/state restoration.** No `PopScope` on the drawing pad ("discard drawing?"), no confirmation on overwriting a skin, `_currentModel` always resets to `assets/akr.glb` on restart, no `RestorationMixin`.

---

## 7. Missing capability vs. what the plugin already offers

The app uses ~10 % of `interactive_3d` and 0 % of what makes a "skin creator" a product:

| Capability | Plugin API (already available) | App |
|---|---|---|
| Per-part base-color texture | `setEntityTexture(s)`, `initialEntityTextures` | broken (SB-01) |
| Remove a texture | `resetEntityTexture`, `resetAllEntityTextures` | absent |
| Colour / metallic / roughness / emissive | `setEntityMaterial`, `initialMaterialOverrides` | absent |
| Persist design | `initialMaterialOverrides` + `initialEntityTextures` | absent |
| Camera reset / zoom buttons | `resetCamera`, `zoomBy`, `setCameraZoomLevel` | absent |
| Load/error UI | `loadingWidget`, `errorBuilder`, `onModelLoaded`, `onModelLoadError` | absent |
| Part picking (tap a part to paint it) | `onSelectionChanged` | absent — the whole gun is painted blindly |
| Hide groups | `updatePartGroupConfig` | absent |

Feature gaps for users: no undo/redo, no eraser, no brush size, no colour picker (5 swatches), no layers, no symmetry, no sticker placement, no UV template, no model search/filter/category, no favourites, no share/export, no skin naming, no gallery sorting, no empty-state CTA, no onboarding, no localization, no analytics/crash reporting.

---

## 8. Prioritized remediation plan

**Day 1 — make the core loop true (P0)**

1. Add `assets/catalog.json` (Appendix A) and wire `_applyTag`/brush to `setEntityTextures` over the model's body entities. Log real runtime names once via `onSelectionChanged` to confirm Android/iOS parity.
2. Add `_modelReady` gating via `onModelLoaded`/`onModelLoadError`; disable tag/brush/publish until ready; replace all `catch` swallows with user-visible errors.
3. Decide the tag-asset strategy: previews for the picker grid, real atlases for texturing (SB-02). Ship at least 3–5 correct 1024² atlases or tileable patterns for testing.
4. Replace SharedPreferences blobs with files in app documents + a JSON index; cap screenshot size; add delete.

**Day 2 — robustness and UX (P1)**

5. Pin `interactive_3d: ^2.5.0`, add `flutter: '>=3.44.0'`, commit `pubspec.lock`.
6. Make the control panel scrollable + `SafeArea`; test landscape/keyboard/font-scale.
7. Rebuild the brush: atlas-ratio canvas, UV guide, devicePixelRatio capture, stroke list + undo/eraser/size/colour picker, `mounted` checks, awaited `setEntityTextures`, success/failure feedback.
8. Persist the design per model and restore with `initialEntityTextures`; add "Сбросить скин".
9. Replace free-text tags with a browsable grid built from the catalog manifest.

**Day 3 — ship quality (P1/P2)**

10. `flutter create . --org <real-org> --platforms=android,ios`, commit platform folders, add `.gitignore`, README, LICENSE, `analysis_options.yaml`, `flutter_lints`, `flutter_test`.
11. Tests: catalog integrity test (every entity name in the map exists in the GLB), tag resolution test, publish/gallery round-trip test.
12. CI: Linux runner, pinned Flutter, Gradle/pub cache, `flutter analyze`, `flutter test`, `flutter build appbundle --release --split-per-abi` (or `--target-platform android-arm64`), signing via env secrets, `--build-name/--build-number` from git tag.
13. Accessibility/localization pass; crash reporting; remove dead white container; tidy theme.

---

## 9. Minimal patch sketch (reference)

```dart
// lib/src/catalog.dart  (generated from the GLBs — see Appendix A)
const Map<String, List<String>> kBodyEntities = {
  'assets/akr.glb':  ['Gunlock1', 'Magazine1', 'LOD_Template'],
  'assets/butterfly.glb': ['Butterfly'],
  // …46 models
};

// lib/main.dart (state)
bool _modelReady = false;
Uint8List? _currentTexture;

Future<void> _applyTexture(Uint8List bytes) async {
  final names = kBodyEntities[_currentModel];
  if (names == null || names.isEmpty) { _toast('Тег недоступен для этой модели', error: true); return; }
  if (!_modelReady) { _toast('Модель ещё загружается', error: true); return; }
  await _controller.setEntityTextures(
    [for (final n in names) EntityTexture(name: n, bytes: bytes)],
  );
  if (!mounted) return;
  setState(() => _currentTexture = bytes);
  _toast('Тег применён');
}

// restore after model switch / restart
Interactive3d(
  key: ValueKey(_currentModel),
  controller: _controller,
  modelPath: _currentModel,
  initialEntityTextures: _currentTexture == null
      ? null
      : [for (final n in kBodyEntities[_currentModel] ?? const <String>[])
           EntityTexture(name: n, bytes: _currentTexture!)],
  onModelLoaded: () => setState(() => _modelReady = true),
  onModelLoadError: (e, st) => setState(() => _modelReady = false),
  errorBuilder: (c, e) => Center(child: Text('Не удалось загрузить модель\n$e')),
)
```

---

## 10. What remains unverified

- `flutter pub get` / `flutter analyze` / device build — no SDK in this environment.
- Whether `RenderRepaintBoundary.toImage` captures the Android `Texture` content on your Impeller/device — test on a physical device (iOS is expected to fail by design).
- Exact runtime entity names as reported by the plugin on Android and iOS (the plugin warns they can differ by platform). Add `onSelectionChanged: (e) => debugPrint(e.map((x) => x.name).toList().toString())` once and tap the model.
- Filament's 32-bit `x86` ABI availability (affects CI packaging only).
- Whether `flutter create`'s current default `minSdk` is already ≥ 24 for the Flutter version Codemagic resolves.

---

## Appendix A — body entity map (computed from the 46 GLBs)

Body meshes only; stickers, StatTrak, sights/lenses, cartridges, bullets, handles-on-grenades excluded. Verify once at runtime; the plugin documents that names may differ between Android and iOS.

| Model | Entities to texture |
|---|---|
| `akimbouzi` | `Gunlock1`, `Gunlock2`, `Handle1`, `Handle2`, `Magazine1` |
| `akr` | `Gunlock1`, `Magazine1`, `LOD_Template` |
| `akr12` | `Gunlock1`, `Magazine1`, `Sight`, `LOD_Template` |
| `awm` | `Gunlock1`, `Gunlock2`, `Magazine1`, `LOD_Template` |
| `berettas` | `Gunlock1`, `Gunlock2`, `Handle1`, `Handle2`, `Magazine1` |
| `butterfly` | `Butterfly` |
| `deagle` | `Gunlock1`, `Magazine1`, `LOD_Template` |
| `dualdaggers` | `L0_LOD0_R` |
| `fabm` | `Gunlock1`, `Handle1`, `LOD_Template` |
| `famas` | `Gunlock1`, `Magazine1`, `LOD_Template` |
| `fang` | `Fang_1` |
| `flash` | `LOD0_Mono` |
| `flip` | `Blade1`, `L0_LOD0_14` |
| `fnfal` | `Gunlock1`, `Magazine1`, `LOD_Template` |
| `fs` | `Gunlock1`, `Magazine1`, `LOD_Template` |
| `g22` | `Gunlock1`, `Magazine1`, `LOD_Template` |
| `he` | `LOD0_Mono.001` |
| `jkommando` | `Jagdkommando_LOD0` |
| `karambit` | `Karambit_1` |
| `kukri` | `L0_LOD0_16` |
| `kunai` | `L0_LOD0_15` |
| `m110` | `Gunlock1.001`, `Magazine1.001`, `LOD_Template.001` |
| `m16` | `Gunlock1.001`, `Magazine1.001`, `Sight`, `LOD_Template.001` |
| `m40` | `Gunlock1`, `Magazine1`, `LOD_Template` |
| `m4a1` | `Gunlock1`, `Magazine1`, `LOD_Template` |
| `m60` | `Gunlock1.001`, `Gunlock2`, `Magazine1.001`, `Sight`, `LOD_Template.001` |
| `m9` | `M9Bayonet_LOD0` |
| `mac10` | `Gunlock1.001`, `Handle1`, `Handle2`, `Magazine1.001`, `LOD_Template.001` |
| `mallard` | `Gunlock1.001`, `Handle1`, `Handle2`, `Magazine1.001`, `Lod_Template.001` |
| `mantis` | `SubMesh_0` |
| `molotov` | `Magazine3`, `LOD0_Template` |
| `mp5` | `Gunlock1.001`, `Magazine1.001`, `LOD_Template.001` |
| `mp7` | `Gunlock1.001`, `Magazine1.001`, `LOD_Template.001` |
| `p350` | `Gunlock1.001`, `Magazine1.001`, `LOD_Template.001` |
| `p90` | `Gunlock1.001`, `Magazine1.001`, `LOD_Template.001` |
| `scorpion` | `Scorpion_Knife` |
| `sm1014` | `Gunlock1.002`, `LOD_Template.001` |
| `smoke` | `LOD0_Mono` |
| `spas` | `Gunlock1.001`, `Gunlock2`, `Magazine3`, `LOD_Template.001` |
| `stiletto` | `Stiletto` |
| `sting` | `L0_LOD0_17` |
| `tanto` | `Tanto_1` |
| `tec9` | `Gunlock1.001`, `Magazine1.001`, `LOD_Template.001` |
| `ump45` | `Gunlock1.001`, `LOD_Template.001` |
| `usp` | `Gunlock1.001`, `Magazine1.001`, `LOD_Template.001` |
| `val` | `Gunlock1.001`, `Magazine1.001`, `LOD_Template.001` |

## Appendix B — tag assets (24, all 1280×591, all previews with UI chrome)

`carbon, chameleon, daybreak, digital burst, dust devil, fury, geometric, haunt, hunter, lich, monster, nebula, necromancer, noxious, posion, radiation, samurai, scratch, sport v2, stone cold, thorn, tiger, venom, winter sport`

Naming notes at the audited revision: `posion` is a typo; nine names contain a space; every image is a weapon-specific store render (`G22 "CARBON"`, `M4 "TIGER"`, `AKR "DIGITAL BURST"`, …) and includes a "НАЗАД" button — none is a texture. A `posion.jpg` → `poison.jpg` rename is staged in the working tree but is outside the audited revision; the code and asset references must be updated together to preserve compatibility.

## Appendix C — asset invariants checked

- 46/46 GLB: valid magic/version, declared length == file size, single JSON chunk parseable, exactly one scene, no trailing bytes, no duplicate files.
- 46/46: at least one mesh with `TEXCOORD_0` (texturing is possible); on each model at least one mesh spans >90 % of 0…1 in both UV axes, while secondary body meshes sample sub-rectangles.
- Embedded base color maps: 512×512 (AKR/M4 family) or 1024×1024 (`flash`), i.e. **square atlases**, versus 1280×591 tag JPEGs → aspect and layout mismatch.
- Code model list vs disk: 46 entries, 46 files, exact match both ways (no missing/extra paths).
- Tracked files: 73 (3 source + 46 GLB + 24 JPEG); no platform folders, no `.gitignore`, no tests, no docs.
