// lib/screens/about_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/log_service.dart';
import 'onboarding_screen.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = 'Carregando...';
  bool _isDiagnosticMode = false;

  @override
  void initState() {
    super.initState();
    // ✅ Atribuição direta — setState() em initState é anti-pattern.
    _isDiagnosticMode = LogService.isDiagnosticMode;
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = 'Versão ${info.version} (build ${info.buildNumber})';
    });
  }

  // ---------------------------------------------------------------------------
  // Rever Tutorial (onboarding)
  // ---------------------------------------------------------------------------
  void _openOnboardingReview() {
    final NavigatorState navigator = Navigator.of(context);

    // A OnboardingScreen persiste a flag novamente — operação idempotente
    // (já era `true`). O que muda é apenas o `onComplete`: em vez de trocar a
    // árvore para HomeScreen, retornamos para esta AboutScreen.
    navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => OnboardingScreen(
          onComplete: () => navigator.pop(),
        ),
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Política de Privacidade'),
        content: const SingleChildScrollView(
          child: Text(
            'O Mirandatune não coleta, armazena ou transmite nenhum dado pessoal.\n\n'
            '• Microfone: Usado apenas enquanto a tela de afinação está ativa. Nenhum áudio é gravado ou enviado.\n\n'
            '• Rede: O app não faz requisições de rede durante o uso normal.\n\n'
            '• Logs de diagnóstico: Salvos apenas no seu aparelho. Só são compartilhados se você tocar explicitamente em "Exportar Logs".\n\n'
            '• Contas: O app não exige cadastro.\n\n'
            'Última atualização: Outubro de 2026.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLogs() async {
    final List<File> files = await LogService.getLogFiles();
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum log encontrado para exportar.')),
        );
      }
      return;
    }

    if (mounted) {
      await Share.shareXFiles(
        files.map((File f) => XFile(f.path)).toList(),
        subject: 'Mirandatune - Logs de Diagnóstico',
      );
    }
  }

  Future<void> _clearLogs() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Limpar Logs'),
        content: const Text(
          'Tem certeza que deseja apagar todos os logs de diagnóstico? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LogService.clearLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logs apagados com sucesso.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sobre o Mirandatune'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: <Widget>[
          // ===== SEÇÃO 1: IDENTIDADE E SOBRE =====
          const SizedBox(height: 20),
          const Icon(Icons.music_note, size: 80, color: Colors.blueAccent),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Mirandatune',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          Center(
            child: Text(
              _version,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Afinador offline para cordas e bateria. Sem anúncios, sem coleta de dados, open source.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse('https://github.com/Marcoferrera/Mirandatune'),
            ),
            icon: const Icon(Icons.link),
            label: const Text('Ver no GitHub'),
          ),

          const SizedBox(height: 8),

          // ✅ Acesso ao tutorial (onboarding)
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Rever Tutorial'),
            subtitle: const Text('Reveja as telas de boas-vindas'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: _openOnboardingReview,
            contentPadding: EdgeInsets.zero,
          ),

          const Divider(height: 40, color: Colors.grey),

          // ===== SEÇÃO 2: PRIVACIDADE E LICENÇAS =====
          const Text(
            'PRIVACIDADE E LICENÇAS',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('Política de Privacidade'),
            onTap: _showPrivacyPolicy,
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Licenças de Terceiros'),
            onTap: () => showLicensePage(context: context),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              '© 2026 Marcos Aurelio Ferreira Miranda — MIT License',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),

          const Divider(height: 40, color: Colors.grey),

          // ===== SEÇÃO 3: DIAGNÓSTICO (DISCRETA) =====
          const Text(
            'DIAGNÓSTICO',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.save, size: 20),
            title: const Text('Salvar Estado Atual', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Salva o buffer de leituras atual em disco'),
            onTap: () async {
              await LogService.saveSnapshot();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Estado salvo com sucesso.')),
                );
              }
            },
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(Icons.ios_share, size: 20),
            title: const Text('Exportar Logs', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Compartilhar logs para análise de bugs'),
            onTap: _exportLogs,
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            title: const Text(
              'Limpar Logs',
              style: TextStyle(fontSize: 14, color: Colors.red),
            ),
            onTap: _clearLogs,
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report, size: 20),
            title: const Text('Modo Diagnóstico', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Grava todas as leituras continuamente em arquivo'),
            value: _isDiagnosticMode,
            onChanged: (bool value) async {
              await LogService.setDiagnosticMode(value);
              setState(() {
                _isDiagnosticMode = value;
              });
            },
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}