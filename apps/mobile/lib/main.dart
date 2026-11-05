// lib/main.dart
import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/strings_tuner_screen.dart';
import 'screens/drum_menu_screen.dart';
import 'screens/about_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/log_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  await LogService.init();

  FlutterError.onError = (FlutterErrorDetails details) {
    LogService.saveErrorLog(details.exception.toString(), details.stack);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    LogService.saveErrorLog(error.toString(), stack);
    return true;
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mirandatune',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool? _onboardingCompleted;

  @override
  void initState() {
    super.initState();
    _loadOnboardingState();
  }

  Future<void> _loadOnboardingState() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool completed =
          prefs.getBool(OnboardingScreen.prefKey) ?? false;

      if (!mounted) return;
      setState(() => _onboardingCompleted = completed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _onboardingCompleted = false);
    }
  }

  Future<void> _handleOnboardingComplete() async {
    if (!mounted) return;
    setState(() => _onboardingCompleted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingCompleted == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    return _onboardingCompleted!
        ? const HomeScreen()
        : OnboardingScreen(onComplete: _handleOnboardingComplete);
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mirandatune'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          if (kDebugMode)
            IconButton(
              tooltip: 'Rever onboarding (debug)',
              icon: const Icon(Icons.restart_alt),
              onPressed: () async {
                final SharedPreferences prefs =
                    await SharedPreferences.getInstance();
                await prefs.remove(OnboardingScreen.prefKey);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Flag apagada. Feche e reabra o app para ver o onboarding.',
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 40),
              const Text(
                'O que vamos afinar hoje?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              _buildMenuCard(
                context,
                title: 'Cordas',
                subtitle: 'Violão, Baixo, Ukulele...',
                icon: Icons.tune,
                color: Colors.blueAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const StringsTunerScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              _buildMenuCard(
                context,
                title: 'Bateria',
                subtitle: 'Bumbo, Tom, Equalização de Parafusos',
                icon: Icons.album,
                color: Colors.orangeAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const DrumMenuScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 60),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Colors.grey,
                ),
                label: const Text(
                  'Sobre o App',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5), width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 60, color: color),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}