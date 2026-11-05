import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogService {
  // Buffer circular em memória (guarda as últimas 300 leituras)
  static final List<Map<String, dynamic>> _buffer = [];
  static const int _maxBufferSize = 300;

  // Configurações de arquivo (Conforme aprovado pelo Qwen)
  static const int _maxFileSizeBytes = 500 * 1024; // 500KB
  static const int _maxLogFiles = 3;

  // Estado do Modo Diagnóstico
  static bool _isDiagnosticMode = false;
  static bool get isDiagnosticMode => _isDiagnosticMode;

  /// Inicializa o serviço carregando a preferência do Modo Diagnóstico
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isDiagnosticMode = prefs.getBool('diagnostic_mode') ?? false;
  }

  /// Ativa/Desativa o Modo Diagnóstico e salva a preferência
  static Future<void> setDiagnosticMode(bool enabled) async {
    _isDiagnosticMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('diagnostic_mode', enabled);
  }

  /// Adiciona uma leitura do DSP ao buffer (e salva em disco se o Modo Diagnóstico estiver ligado)
  static void logReading({
    required String drumType,
    required double f0,
    required double f1,
    required double rtf,
    required double rms,
  }) {
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'READING',
      'drum': drumType,
      'f0': double.parse(f0.toStringAsFixed(1)),
      'f1': double.parse(f1.toStringAsFixed(1)),
      'rtf': double.parse(rtf.toStringAsFixed(2)),
      'rms': double.parse(rms.toStringAsFixed(3)),
    };

    _buffer.add(entry);
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0); // Remove o mais antigo
    }

    // Se o modo diagnóstico estiver ligado, salva no disco imediatamente
    if (_isDiagnosticMode) {
      _appendToDisk(entry);
    }
  }

  /// Adiciona um evento de sistema (ex: mudou de modo)
  static void addEvent(String type, Map<String, dynamic> data) {
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'type': type,
      'data': data,
    };
    _buffer.add(entry);
    if (_buffer.length > _maxBufferSize) _buffer.removeAt(0);
  }

  /// Salva o estado atual do buffer em um arquivo (Botão "Salvar Estado Atual")
  static Future<void> saveSnapshot() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/snapshot_${DateTime.now().millisecondsSinceEpoch}.txt');
      
      final content = StringBuffer();
      content.writeln('=== SNAPSHOT DE DIAGNÓSTICO ===');
      content.writeln('Data: ${DateTime.now()}');
      content.writeln('Total de leituras no buffer: ${_buffer.length}');
      content.writeln('---');
      
      for (var entry in _buffer) {
        content.writeln(jsonEncode(entry));
      }
      
      await file.writeAsString(content.toString());
      print('Snapshot salvo em: ${file.path}');
    } catch (e) {
      print('Erro ao salvar snapshot: $e');
    }
  }

  /// Salva um erro crítico no disco (Chamado pelos Error Handlers do Flutter)
  static Future<void> saveErrorLog(String error, StackTrace? stack) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/error_log.txt');
      
      final content = StringBuffer();
      content.writeln('=== ERRO CRÍTICO ===');
      content.writeln('Data: ${DateTime.now()}');
      content.writeln('Erro: $error');
      if (stack != null) content.writeln('Stack Trace:\n$stack');
      content.writeln('\n=== ÚLTIMAS LEITURAS (CONTEXTO) ===');
      
      for (var entry in _buffer) {
        content.writeln(jsonEncode(entry));
      }
      
      await file.writeAsString(content.toString());
      print('Error log salvo em: ${file.path}');
    } catch (e) {
      print('Falha ao salvar error log: $e');
    }
  }

  /// Grava uma entrada no arquivo de log rotativo (Modo Diagnóstico)
  static Future<void> _appendToDisk(Map<String, dynamic> entry) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/log_diagnostic.txt');

      // Verifica o tamanho do arquivo para rotação
      if (await file.exists()) {
        final length = await file.length();
        if (length > _maxFileSizeBytes) {
          await _rotateLogs(dir);
        }
      }

      await file.writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append);
    } catch (e) {
      print('Erro ao escrever no log: $e');
    }
  }

  /// Rotaciona os arquivos (deleta o mais antigo, renomeia os outros)
  static Future<void> _rotateLogs(Directory dir) async {
    final file2 = File('${dir.path}/log_diagnostic_2.txt');
    final file1 = File('${dir.path}/log_diagnostic_1.txt');
    final file0 = File('${dir.path}/log_diagnostic.txt');

    if (await file2.exists()) await file2.delete();
    if (await file1.exists()) await file1.rename(file2.path);
    if (await file0.exists()) await file0.rename(file1.path);
  }

  /// Retorna a lista de arquivos de log disponíveis para exportação
  static Future<List<File>> getLogFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final List<File> files = [];
    
    final List<String> filenames = [
      'error_log.txt',
      'log_diagnostic.txt',
      'log_diagnostic_1.txt',
      'log_diagnostic_2.txt',
    ];

    for (var name in filenames) {
      final file = File('${dir.path}/$name');
      if (await file.exists()) files.add(file);
    }

    // Adiciona também os snapshots manuais
    final entities = dir.listSync();
    for (var entity in entities) {
      if (entity is File && entity.path.contains('snapshot_')) {
        files.add(entity);
      }
    }

    return files;
  }

  /// Apaga todos os arquivos de log do app
  static Future<void> clearLogs() async {
    final dir = await getApplicationDocumentsDirectory();
    final entities = dir.listSync();
    
    for (var entity in entities) {
      if (entity is File && (entity.path.contains('log') || entity.path.contains('snapshot'))) {
        await entity.delete();
      }
    }
    _buffer.clear();
  }
}