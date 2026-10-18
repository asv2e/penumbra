import 'package:flutter/material.dart';

import 'project_store.dart';
import 'projects_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ProjectStore.instance.init();
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
      home: const ProjectsPage(),
    );
  }
}
