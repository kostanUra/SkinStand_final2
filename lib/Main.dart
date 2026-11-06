import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle; 
import 'package:interactive_3d/interactive_3d.dart';

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

  // 👇 СПИСОК ТВОИХ МОДЕЛЕЙ (проверь точные названия файлов)
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
    'assets/g22.glb',
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

  // --- МОЗГ ИГРЫ: Поиск картинки по тегу (.jpg или .png) ---
  Future<void> applyTag(String tag) async {
    String cleanTag = tag.trim().toLowerCase();
    if (cleanTag.isEmpty) return;

    ByteData? imageData;

    // 1. Пытаемся загрузить JPG
    try {
      imageData = await rootBundle.load('assets/tags/$cleanTag.jpg');
    } catch (e) {
      // 2. Если JPG нет, пытаемся загрузить PNG
      try {
        imageData = await rootBundle.load('assets/tags/$cleanTag.png');
      } catch (e) {
        // Если ни того, ни другого нет
      }
    }

    if (imageData != null) {
      Uint8List bytes = imageData.buffer.asUint8List();
      
      // ⚠️ ВАЖНО: 'Material' — это имя материала внутри твоей 3D-модели.
      // Если текстура не применяется, попробуй поменять 'Material' на 'DefaultMaterial' или 'Base'.
      _controller.setEntityTexture('Material', bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Тег "$cleanTag" применен к скину!'), backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Картинка для тега "$cleanTag" не найдена (нужен .jpg или .png)'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('КРЕАТОР СКИНОВ'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 3D-Вьювер
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              child: Interactive3d(
                key: ValueKey(_currentModel), 
                controller: _controller,
                modelPath: _currentModel,
              ),
            ),
          ),

          // Панель инструментов
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: const BoxDecoration(
              color: Color(0xFF222222),
              border: Border(top: BorderSide(color: Colors.black54, width: 2)),
              ),
            child: Column(
              children: [
                // Выпадающий список оружия
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade700),
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
                        child: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

                // Поле ввода тега и кнопка "Применить"
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
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          applyTag(_tagController.text); // Вызов мозга игры
                        },
                        child: const Text('ТЕГ', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 10),

                // Кнопка "Выложить"
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange, 
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  onPressed: () {
                     ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скин сохранен!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.orange),
                    );
                  },
                  child: const Text('ВЫЛОЖИТЬ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}