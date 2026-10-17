import 'package:flutter/material.dart';

import 'editor_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PenumbraApp());
}

class PenumbraApp extends StatelessWidget {
  const PenumbraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Penumbra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4DB6AC),
      ),
      home: const EditorPage(),
    );
  }
}
