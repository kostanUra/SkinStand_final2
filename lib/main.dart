import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:interactive_3d/interactive_3d.dart';

import 'src/catalog.dart';
import 'src/data/skin_index.dart';
import 'src/data/skin_store.dart';
import 'src/theme.dart';

void main() {
  runApp(const SkinStandApp());
}

class SkinStandApp extends StatelessWidget {
  const SkinStandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3D Skin Creator',
      debugShowCheckedModeBanner: false,
      theme: SkinStandTheme.build(),
      home: const CreatorScreen(),
    );
  }
}

class CreatorScreen extends StatefulWidget {
  const CreatorScreen({super.key});

  @override
  State<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends State<CreatorScreen> {
  final Interactive3dController _controller = Interactive3dController();
  final GlobalKey _repaintKey = GlobalKey();
  final Map<String, StoredDesign?> _designs = <String, StoredDesign?>{};

  Catalog? _catalog;
  TagCatalog? _tagCatalog;
  SkinStore? _store;
  ModelInfo? _currentModel;
  StoredDesign? _currentDesign;
  String? _initializationError;
  String? _pendingModelId;
  int _modelRequest = 0;
  bool _modelReady = false;
  bool _isInitializing = true;
  bool _isApplying = false;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _isInitializing = true;
      _initializationError = null;
    });
    try {
      final Catalog catalog =
          Catalog.parse(await rootBundle.loadString('assets/catalog.json'));
      final TagCatalog tags =
          TagCatalog.parse(await rootBundle.loadString('assets/tags/manifest.json'));
      final SkinStore store = await SkinStore.open();
      final String? lastModelId = await store.loadLastModelId();
      final ModelInfo model = catalog.byId(lastModelId) ?? catalog.models.first;
      final StoredDesign? design = await store.loadDesign(model.id);

      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = catalog;
        _tagCatalog = tags;
        _store = store;
        _currentModel = model;
        _currentDesign = design;
        _designs[model.id] = design;
        _isInitializing = false;
      });
    } on Object catch (error, stackTrace) {
      debugPrint('SkinStand initialization failed: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _initializationError = error.toString();
        _isInitializing = false;
      });
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? SkinStandTheme.danger : SkinStandTheme.success,
        ),
      );
  }

  Future<void> _selectModel(ModelInfo model) async {
    final SkinStore? store = _store;
    if (store == null || model.id == _currentModel?.id) {
      return;
    }
    final int request = ++_modelRequest;
    _pendingModelId = model.id;
    setState(() {
      _modelReady = false;
    });

    StoredDesign? design;
    try {
      design = _designs.containsKey(model.id)
          ? _designs[model.id]
          : await store.loadDesign(model.id);
    } on Object catch (error, stackTrace) {
      debugPrint('Could not restore design for ${model.id}: $error\n$stackTrace');
      _showMessage('Не удалось загрузить сохранённый дизайн: $error', isError: true);
    }
    if (!mounted || request != _modelRequest) {
      return;
    }
    _pendingModelId = null;
    setState(() {
      _currentModel = model;
      _currentDesign = design;
      _designs[model.id] = design;
    });
    await store.saveLastModelId(model.id);
  }

  void _onModelLoaded(String modelId) {
    if (!mounted || _pendingModelId != null || _currentModel?.id != modelId) {
      return;
    }
    setState(() => _modelReady = true);
  }

  void _onModelLoadError(String modelId, Object error, StackTrace? stackTrace) {
    debugPrint('Could not load model $modelId: $error\n$stackTrace');
    if (!mounted || _pendingModelId != null || _currentModel?.id != modelId) {
      return;
    }
    setState(() => _modelReady = false);
    _showMessage('Не удалось загрузить модель: $error', isError: true);
  }

  Future<void> _applyTexture(Uint8List bytes, {String? tagId}) async {
    final ModelInfo? model = _currentModel;
    final SkinStore? store = _store;
    if (model == null || store == null || !_modelReady || _isPublishing) {
      throw StateError('Дождитесь загрузки 3D-модели.');
    }
    if (_isApplying) {
      throw StateError('Дождитесь завершения предыдущей операции.');
    }

    setState(() => _isApplying = true);
    try {
      await _controller.setEntityTextures(<EntityTexture>[
        for (final String entity in model.bodyEntities)
          EntityTexture(name: entity, bytes: bytes),
      ]);

      final StoredDesign design = StoredDesign(bytes: bytes, tagId: tagId);
      if (mounted && _currentModel?.id == model.id) {
        setState(() {
          _currentDesign = design;
          _designs[model.id] = design;
        });
      }
      try {
        await store.saveDesign(model.id, bytes, tagId: tagId);
      } on Object catch (error, stackTrace) {
        debugPrint('Texture applied but could not be persisted: $error\n$stackTrace');
        throw StateError('Текстура применена, но не сохранена: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  Future<void> _chooseTag() async {
    final TagCatalog? catalog = _tagCatalog;
    if (catalog == null || !_modelReady || _isApplying || _isPublishing) {
      _showMessage('Сначала дождитесь загрузки модели.', isError: true);
      return;
    }

    final TagInfo? tag = await showModalBottomSheet<TagInfo>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _TagPicker(tags: catalog.tags),
    );
    if (tag == null || !mounted) {
      return;
    }

    try {
      final ByteData data = await rootBundle.load(tag.texture);
      final Uint8List bytes = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      await _applyTexture(bytes, tagId: tag.id);
      _showMessage('Тег «${tag.name}» применён и сохранён.');
    } on Object catch (error, stackTrace) {
      debugPrint('Could not apply tag ${tag.id}: $error\n$stackTrace');
      _showMessage('Не удалось применить тег: $error', isError: true);
    }
  }

  Future<void> _openBrush() async {
    if (!_modelReady || _isApplying || _isPublishing) {
      _showMessage('Сначала дождитесь загрузки модели.', isError: true);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DrawingPad(
          onSave: (Uint8List bytes) async {
            await _applyTexture(bytes);
            _showMessage('Рисунок применён и сохранён.');
          },
        ),
      ),
    );
  }

  Future<void> _resetDesign() async {
    final ModelInfo? model = _currentModel;
    final SkinStore? store = _store;
    if (model == null ||
        store == null ||
        !_modelReady ||
        _isApplying ||
        _isPublishing) {
      return;
    }
    setState(() => _isApplying = true);
    try {
      await _controller.resetAllEntityTextures();
      await store.deleteDesign(model.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentDesign = null;
        _designs[model.id] = null;
      });
      _showMessage('Дизайн сброшен.');
    } on Object catch (error, stackTrace) {
      debugPrint('Could not reset design: $error\n$stackTrace');
      _showMessage('Не удалось сбросить дизайн: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  Future<void> _publishSkin() async {
    final ModelInfo? model = _currentModel;
    final SkinStore? store = _store;
    if (model == null || store == null || !_modelReady || _isPublishing) {
      _showMessage('Сначала дождитесь загрузки модели.', isError: true);
      return;
    }
    final String? tagId = _currentDesign?.tagId;
    setState(() => _isPublishing = true);

    ui.Image? image;
    try {
      if (!kIsWeb && Platform.isIOS) {
        throw UnsupportedError(
          'Сохранение снимка 3D-модели пока не поддерживается на iOS.',
        );
      }
      final RenderObject? renderObject =
          _repaintKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
        throw StateError('Область модели ещё не готова к снимку.');
      }
      final Size size = renderObject.size;
      final double maxPixelRatio = 1600 / math.max(size.width, size.height);
      final double pixelRatio = math.min(
        MediaQuery.devicePixelRatioOf(context),
        maxPixelRatio,
      ).clamp(0.05, 2.0).toDouble();
      image = await renderObject.toImage(pixelRatio: pixelRatio);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes == 0) {
        throw StateError('Не удалось закодировать изображение.');
      }
      final Uint8List png = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      await store.add(png, model: model, tagId: tagId);
      if (mounted) {
        _showMessage('Скин сохранён в галерею.');
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Could not publish skin: $error\n$stackTrace');
      _showMessage('Не удалось сохранить скин: $error', isError: true);
    } finally {
      image?.dispose();
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  void _openGallery() {
    final SkinStore? store = _store;
    if (store == null) {
      _showMessage('Галерея пока недоступна.', isError: true);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GalleryScreen(store: store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_initializationError != null || _catalog == null || _currentModel == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SKINSTAND')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, color: SkinStandTheme.accent, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Не удалось запустить приложение.\n${_initializationError ?? ''}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _initialize, child: const Text('Повторить')),
              ],
            ),
          ),
        ),
      );
    }

    final ModelInfo model = _currentModel!;
    final StoredDesign? design = _currentDesign;
    final List<EntityTexture>? initialTextures = design == null
        ? null
        : <EntityTexture>[
            for (final String entity in model.bodyEntities)
              EntityTexture(name: entity, bytes: design.bytes),
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('КРЕАТОР'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Мои скины',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _openGallery,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: RepaintBoundary(
              key: _repaintKey,
              child: Interactive3d(
                key: ValueKey<String>(model.id),
                controller: _controller,
                modelPath: model.glb,
                initialEntityTextures: initialTextures,
                backgroundColor: SkinStandTheme.background,
                loadingWidget: const Center(child: CircularProgressIndicator()),
                errorBuilder: (BuildContext context, Object error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Не удалось загрузить модель.\n$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
                onModelLoaded: () => _onModelLoaded(model.id),
                onModelLoadError: (Object error, StackTrace? stackTrace) =>
                    _onModelLoadError(model.id, error, stackTrace),
              ),
            ),
          ),
          Flexible(
            flex: 2,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(model.id),
                      initialValue: model.id,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Модель'),
                      items: <DropdownMenuItem<String>>[
                        for (final ModelInfo entry in _catalog!.models)
                          DropdownMenuItem<String>(
                            value: entry.id,
                            child: Text('${entry.name} · ${entry.category}'),
                          ),
                      ],
                      onChanged: _isApplying || _isPublishing
                          ? null
                          : (String? id) {
                              final ModelInfo? selected = _catalog!.byId(id);
                              if (selected != null) {
                                _selectModel(selected);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _modelReady && !_isApplying && !_isPublishing
                                ? _chooseTag
                                : null,
                            icon: const Icon(Icons.palette_outlined),
                            label: Text(
                              _currentDesign?.tagId == null
                                  ? 'ВЫБРАТЬ ТЕГ'
                                  : 'ТЕГ: ${_tagCatalog?.byId(_currentDesign!.tagId)?.name ?? 'свой рисунок'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Рисовать',
                          onPressed: _modelReady && !_isApplying && !_isPublishing
                              ? _openBrush
                              : null,
                          icon: const Icon(Icons.brush_outlined),
                        ),
                        IconButton(
                          tooltip: 'Сбросить дизайн',
                          onPressed: _modelReady &&
                                  _currentDesign != null &&
                                  !_isApplying &&
                                  !_isPublishing
                              ? _resetDesign
                              : null,
                          icon: const Icon(Icons.restart_alt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _modelReady && !_isApplying && !_isPublishing
                          ? _publishSkin
                          : null,
                      child: _isPublishing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('СОХРАНИТЬ В ГАЛЕРЕЮ'),
                    ),
                    if (!_modelReady) ...<Widget>[
                      const SizedBox(height: 8),
                      const Text(
                        'Загрузка модели…',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagPicker extends StatelessWidget {
  const _TagPicker({required this.tags});

  final List<TagInfo> tags;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('ВЫБЕРИТЕ ТЕКСТУРУ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: tags.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.9,
                ),
                itemBuilder: (BuildContext context, int index) {
                  final TagInfo tag = tags[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).pop(tag),
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              tag.preview,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (context, error, stackTrace) => ColoredBox(
                                color: tag.accent.withValues(alpha: 0.2),
                                child: Center(
                                  child: Icon(Icons.texture, color: tag.accent),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            tag.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({required this.store, super.key});

  final SkinStore store;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _isDeleting = false;

  Future<void> _deleteSkin(SavedSkin skin) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Удалить скин?'),
        content: Text('«${skin.modelName}» будет удалён из галереи.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ОТМЕНА'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('УДАЛИТЬ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await widget.store.delete(skin);
      if (mounted) {
        setState(() {});
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Could not delete gallery item: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось удалить скин: $error'),
            backgroundColor: SkinStandTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<SavedSkin> skins = widget.store.skins;
    return Scaffold(
      appBar: AppBar(title: const Text('МОИ СКИНЫ')),
      body: skins.isEmpty
          ? const Center(
              child: Text(
                'Галерея пуста. Создайте первый скин!',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: skins.length,
              itemBuilder: (BuildContext context, int index) {
                final SavedSkin skin = skins[index];
                final String? path = widget.store.pathForFile(skin.file);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (path != null)
                        Image.file(
                          File(path),
                          fit: BoxFit.contain,
                          cacheWidth: 480,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(Icons.broken_image_outlined, size: 40),
                          ),
                        )
                      else
                        const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: ColoredBox(
                          color: Colors.black87,
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    skin.modelName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Удалить скин',
                                onPressed: _isDeleting ? null : () => _deleteSkin(skin),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

typedef DrawingSaveCallback = Future<void> Function(Uint8List bytes);

class DrawingPad extends StatefulWidget {
  const DrawingPad({required this.onSave, super.key});

  final DrawingSaveCallback onSave;

  @override
  State<DrawingPad> createState() => _DrawingPadState();
}

class _DrawingPadState extends State<DrawingPad> {
  static const int _textureSize = 1024;
  static const List<Color> _colors = <Color>[
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.black,
    Colors.white,
  ];

  final GlobalKey _canvasKey = GlobalKey();
  final List<_BrushStroke> _strokes = <_BrushStroke>[];
  Color _brushColor = Colors.red;
  int _paintVersion = 0;
  bool _isSaving = false;

  RenderBox? get _canvasBox {
    final RenderObject? object = _canvasKey.currentContext?.findRenderObject();
    return object is RenderBox ? object : null;
  }

  void _startStroke(DragDownDetails details) {
    final RenderBox? box = _canvasBox;
    if (box == null) {
      return;
    }
    setState(() {
      _strokes.add(
        _BrushStroke(
          color: _brushColor,
          points: <Offset>[box.globalToLocal(details.globalPosition)],
        ),
      );
      _paintVersion++;
    });
  }

  void _continueStroke(DragUpdateDetails details) {
    final RenderBox? box = _canvasBox;
    if (box == null || _strokes.isEmpty) {
      return;
    }
    setState(() {
      _strokes.last.points.add(box.globalToLocal(details.globalPosition));
      _paintVersion++;
    });
  }

  Future<void> _saveDrawing() async {
    if (_isSaving) {
      return;
    }
    final RenderObject? object = _canvasKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary || !object.hasSize) {
      _showError('Холст ещё не готов.');
      return;
    }

    setState(() => _isSaving = true);
    ui.Image? image;
    try {
      final double ratio = (_textureSize / object.size.width).clamp(0.5, 4.0).toDouble();
      image = await object.toImage(pixelRatio: ratio);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes == 0) {
        throw StateError('Не удалось закодировать рисунок.');
      }
      final Uint8List bytes = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      await widget.onSave(bytes);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Could not apply drawing: $error\n$stackTrace');
      _showError('Не удалось применить рисунок: $error');
    } finally {
      image?.dispose();
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: SkinStandTheme.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('КИСТЬ'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Применить рисунок',
            onPressed: _isSaving ? null : _saveDrawing,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, color: SkinStandTheme.accent),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double side = math.min(constraints.maxWidth, constraints.maxHeight);
                return Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanDown: _startStroke,
                        onPanUpdate: _continueStroke,
                        child: CustomPaint(
                          foregroundPainter: _SkinPainter(
                            List<_BrushStroke>.of(_strokes),
                            _paintVersion,
                          ),
                          child: const ColoredBox(color: Color(0xFFE9E9E9)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  for (final Color color in _colors)
                    Semantics(
                      button: true,
                      label: 'Цвет кисти',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _brushColor = color),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _brushColor == color
                                  ? SkinStandTheme.accent
                                  : Colors.white38,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Очистить холст',
                    onPressed: () => setState(() {
                      _strokes.clear();
                      _paintVersion++;
                    }),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrushStroke {
  _BrushStroke({required this.color, required this.points});

  final Color color;
  final List<Offset> points;
}

class _SkinPainter extends CustomPainter {
  const _SkinPainter(this.strokes, this.version);

  final List<_BrushStroke> strokes;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    for (final _BrushStroke stroke in strokes) {
      final Paint paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 15
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.single, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      } else if (stroke.points.length > 1) {
        final Path path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (final Offset point in stroke.points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SkinPainter oldDelegate) => version != oldDelegate.version;
}
