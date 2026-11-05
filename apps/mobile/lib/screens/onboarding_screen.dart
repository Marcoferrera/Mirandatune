// lib/screens/onboarding_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/log_service.dart';

class OnboardingScreen extends StatefulWidget {
  static const String prefKey = 'onboarding_completed';

  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_OnboardingPage> _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.music_note_rounded,
      title: 'Bem-vindo ao Mirandatune',
      description:
          'Afinador profissional 100% offline para cordas e bateria.\n\n'
          'Sem anúncios, sem coleta de dados. Sua privacidade é absoluta.',
      accent: Color(0xFF4FC3F7),
    ),
    _OnboardingPage(
      icon: Icons.music_note,
      title: 'Afinador de Cordas',
      description:
          'Violão, baixo, ukulele e violino. Ajuste capotraste e a '
          'frequência de referência A4.\n\n'
          'Toque a corda e acompanhe a afinação em tempo real.',
      accent: Color(0xFF81C784),
    ),
    _OnboardingPage(
      icon: Icons.album,
      title: 'Afinador de Bateria',
      description:
          'Selecione o tambor, ative o microfone e bata.\n\n'
          'Use o modo Resposta para afinar a pele de resposta. '
          'Use o modo Ataque para afinar a pele de ataque.\n\n'
          'Equalize parafusos em padrão cruzado (estrela).',
      accent: Color(0xFFFFB74D),
    ),
    _OnboardingPage(
      icon: Icons.speed,
      title: 'Calibração de Latência',
      // Texto curto que você sugeriu
      description:
          'Se notar que a agulha está reagindo com atraso, use a função ⚙️ Calibrar latência no rodapé do afinador de tambor.',
      accent: Color(0xFF9575CD),
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  Future<void> _finishOnboarding() async {
    HapticFeedback.mediumImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(OnboardingScreen.prefKey, true);
      LogService.addEvent(
        'ONBOARDING',
        <String, dynamic>{
          'message': 'Concluído na página ${_currentPage + 1}/${_pages.length}',
        },
      );
    } catch (e) {
      LogService.addEvent(
        'ONBOARDING_ERROR',
        <String, dynamic>{'error': 'Falha ao salvar flag: $e'},
      );
    }
    if (!mounted) return;
    widget.onComplete();
  }

  void _goNext() {
    HapticFeedback.selectionClick();
    if (_isLastPage) {
      _finishOnboarding();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.topRight,
                child: Visibility(
                  visible: !_isLastPage,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      'Pular',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (int index) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentPage = index);
                },
                itemBuilder: (BuildContext context, int index) {
                  return _OnboardingPageView(page: _pages[index]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: _buildIndicators(theme),
                  ),
                  FilledButton(
                    onPressed: _goNext,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      _isLastPage ? 'Começar' : 'Próximo',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicators(ThemeData theme) {
    return Row(
      children: List<Widget>.generate(_pages.length, (int index) {
        final bool active = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.4),
          ),
        );
      }),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final Color accent;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
  });
}

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;
  const _OnboardingPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    
    // De volta à estrutura original "Zero Scroll"
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: page.accent.withOpacity(0.12),
              border: Border.all(
                color: page.accent.withOpacity(0.35),
                width: 2,
              ),
            ),
            child: Icon(page.icon, size: 88, color: page.accent),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}