import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_storage.dart';
import 'state/app_controller.dart';

void main() {
  runApp(ChaoxingApp(controller: AppController(DeviceAppStorage())));
}

class ChaoxingApp extends StatelessWidget {
  const ChaoxingApp({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '学习通待办',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF256D85),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFE1E5EA)),
          ),
        ),
      ),
      home: HomeScreen(controller: controller),
    );
  }
}
