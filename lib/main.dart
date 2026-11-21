import 'package:flutter/material.dart';

import 'screens/connection_test_screen.dart';
import 'screens/lobby_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DominoLanApp());
}

class DominoLanApp extends StatelessWidget {
  const DominoLanApp({super.key});

  static const Color felt = Color(0xFF174E3A);
  static const Color gold = Color(0xFFD8B66A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دومينو الشبكة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: felt,
          primary: felt,
          secondary: gold,
          surface: const Color(0xFFF5F7F5),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F5),
        fontFamily: 'Arial',
        appBarTheme: const AppBarTheme(
          backgroundColor: felt,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دومينو الشبكة')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      color: DominoLanApp.felt,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.extension,
                          size: 54,
                          color: DominoLanApp.gold,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'دومينو الشبكة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'أربعة لاعبين • فريقان • دون إنترنت',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ConnectionTestScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.wifi),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('اختبار الاتصال المحلي'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LobbyScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.groups),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('إنشاء غرفة / الانضمام للعب'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'الإصدار التأسيسي 0.1.0',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
