import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:interactive_3d/interactive_3d.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3D Skin Creator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF222222),
          titleTextStyle: TextStyle(color: Colors.orange, fontSize: 20, fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Colors.orange),
        ),
      ),
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
  final TextEditingController _tagController = TextEditingController();
  final GlobalKey _repaintKey = GlobalKey(); // Для скриншота

  final List<String> allModels = [
    'assets/akr.glb',
    'assets/deagle.glb',
    'assets/dualdaggers.glb',
    'assets/fabm.glb',
    'assets/famas.glb',
    'assets/flash.glb',
    'assets/flip.glb',
    'assets/g22.glb',
    'assets/he.glb',
    'assets/karambit.glb',
    'assets/jkommando.glb',
    'assets/akimbouzi.glb',
    'assets/akr12.glb',
    'assets/awm.glb',
    'assets/berettas.glb',
    'assets/butterfly.glb',
    'assets/fang.glb',
    'assets/fnfal.glb',
    'assets/fs.glb',
    'assets/kukri.glb',
    'assets/kunai.glb',
    'assets/m4a1.glb',
    'assets/m9.glb',
    'assets/m16.glb',
    'assets/m40.glb',
    'assets/m60.glb',
    'assets/m110.glb',
    'assets/mac10.glb',
    'assets/mallard.glb',
    'assets/mantis.glb',
    'assets/molotov.glb',
    'assets/mp5.glb',
    'assets/mp7.glb',
    'assets/p90.glb',
    'assets/p350.glb',
    'assets/scorpion.glb',
    'assets/sm1014.glb',
    'assets/smoke.glb',
    'assets/spas.glb',
    'assets/stiletto.glb',
    'assets/sting.glb',
    'assets/tanto.glb',
    'assets/tec9.glb',
    'assets/ump45.glb',
    'assets/usp.glb',
    'assets/val.glb',
  ];

  late String _currentModel;

  @override
  void initState() {
    super.initState();
    _currentModel = allModels.first;
  }

  // --- МОЗГ ИГРЫ: ТЕГИ ---
  Future<void> applyTag(String tag) async {
    String cleanTag = tag.trim().toLowerCase();
    if (cleanTag.isEmpty) return;

    ByteData? imageData;
    // Пытаемся загрузить картинку. Если теги не работают, скорее всего проблема в имени файла.
    try {
      imageData = await rootBundle.load('assets/tags/$cleanTag.jpg');
    } catch (e) {
      try {
        imageData = await rootBundle.load('assets/tags/$cleanTag.png');
      } catch (e) {
        // Если файла нет, покажем ошибку
      }
    }

    if (imageData != null) {
      Uint8List bytes = imageData.buffer.asUint8List();

      // ВАЖНО: Если теги не применяются, значит материал в твоих .glb файлах называется не 'Material'
      // Попробуй поменять 'Material' на 'DefaultMaterial', 'Base' или 'Mat'
      await _controller.setEntityTexture(name: 'Material', bytes: bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Тег "$cleanTag" применен!'), backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл assets/tags/$cleanTag.jpg не найден!'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- КИСТЬ (2D ХОЛСТ) ---
  void openBrush() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DrawingPad(onSave: (bytes) {
        // Когда игрок нарисовал, натягиваем его рисунок на 3D-модель
        _controller.setEntityTexture(name: 'Material', bytes: bytes);
      })),
    );
  }

  // --- ГАЛЕРЕЯ ---
  Future<void> publishSkin() async {
    try {
      // Делаем скриншот 3D-модели
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      // Переводим в Base64 строку для сохранения
      String base64Image = base64Encode(bytes);
      // Сохраняем в память телефона
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> savedSkins = prefs.getStringList('my_skins') ?? [];
      savedSkins.add(base64Image);
      await prefs.setStringList('my_skins', savedSkins);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скин сохранен в галерею!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('$e');
    }
  }

  void openGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GalleryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('КРЕАТОР'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.photo_library), onPressed: openGallery), // Кнопка галереи
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: RepaintBoundary( // Обертка для скриншота
              key: _repaintKey,
              child: Container(
                color: Colors.white,
                child: Interactive3d(
                  key: ValueKey(_currentModel),
                  controller: _controller,
                  modelPath: _currentModel,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12.0),
            color: const Color(0xFF222222),
            child: Column(
              children: [
                // Выбор модели
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: _currentModel,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF333333),
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.orange),
                    items: allModels.map((String modelPath) {
                      String displayName = modelPath.replaceAll('assets/', '').replaceAll('.glb', '').toUpperCase();
                      return DropdownMenuItem<String>(
                        value: modelPath,
                        child: Text(displayName, style: const TextStyle(color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() { _currentModel = newValue; });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // Теги
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _tagController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Тег (fire, neon)...',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          filled: true,
                          fillColor: const Color(0xFF333333),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () => applyTag(_tagController.text),
                      child: const Text('ТЕГ'),
                    ),
                    const SizedBox(width: 8),
                    // Кнопка Кисти
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      onPressed: openBrush,
                      child: const Icon(Icons.brush, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Кнопка сохранения
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: publishSkin,
                  child: const Text('ВЫЛОЖИТЬ В ГАЛЕРЕЮ', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- ЭКРАН ГАЛЕРЕИ ---
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<String> _skins = [];

  @override
  void initState() {
    super.initState();
    _loadSkins();
  }

  Future<void> _loadSkins() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _skins = prefs.getStringList('my_skins') ?? [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('МОИ СКИНЫ')),
      body: _skins.isEmpty
          ? const Center(child: Text('Галерея пуста. Создай первый скин!', style: TextStyle(color: Colors.grey)))
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _skins.length,
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange, width: 2),
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white,
                  ),
                  child: Image.memory(base64Decode(_skins[index]), fit: BoxFit.contain),
                );
              },
            ),
    );
  }
}

// --- ЭКРАН КИСТИ (2D РИСОВАНИЕ) ---
class DrawingPad extends StatefulWidget {
  final Function(Uint8List) onSave;
  const DrawingPad({super.key, required this.onSave});

  @override
  State<DrawingPad> createState() => _DrawingPadState();
}

class _DrawingPadState extends State<DrawingPad> {
  List<Offset> _points = [];
  Color _brushColor = Colors.red;
  final GlobalKey _canvasKey = GlobalKey();

  Future<void> _saveDrawing() async {
    try {
      RenderRepaintBoundary boundary = _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        widget.onSave(byteData.buffer.asUint8List());
        Navigator.pop(context); // Закрываем холст
      }
    } catch (e) {
      debugPrint('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('КИСТЬ'),
        actions: [
          IconButton(icon: const Icon(Icons.save, color: Colors.green), onPressed: _saveDrawing),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RepaintBoundary(
              key: _canvasKey,
              child: Container(
                color: Colors.white, // Белый фон для текстуры
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final RenderBox canvas = _canvasKey.currentContext!.findRenderObject() as RenderBox;
                    setState(() {
                      _points.add(canvas.globalToLocal(details.globalPosition));
                    });
                  },
                  onPanEnd: (details) => setState(() => _points.add(Offset.zero)),
                  child: CustomPaint(
                    painter: SignaturePainter(_points, _brushColor),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var color in [Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.black])
                  GestureDetector(
                    onTap: () => setState(() => _brushColor = color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _brushColor == color ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white),
                  onPressed: () => setState(() => _points.clear()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SignaturePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  SignaturePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 15.0; // Толщина кисти

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != Offset.zero && points[i + 1] != Offset.zero) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}
