import 'package:flutter/material.dart';
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
      theme: ThemeData.dark(),
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
  String _currentModel = ''; 

  @override
  void initState() {
    super.initState();
    // ВАЖНО: Замени 'ak47.glb' на точное имя файла твоей модели!
    _currentModel = 'assets/ak47.glb'; 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Креатор скинов'), backgroundColor: Colors.orange),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              child: Interactive3d(
                controller: _controller,
                modelPath: _currentModel,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.black87,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      // Здесь ты сможешь менять модели (добавь свои имена файлов)
                      onPressed: () => setState(() => _currentModel = 'assets/ak47.glb'),
                      child: const Text('Автомат'),
                    ),
                    ElevatedButton(
                      onPressed: () => setState(() => _currentModel = 'assets/knife.glb'),
                      child: const Text('Нож'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size.fromHeight(50)),
                  onPressed: () {
                     ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скин сохранен!')),
                    );
                  },
                  child: const Text('Выложить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}