// lib/widgets/latency_calibration_dialog.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/log_service.dart';

class LatencyCalibrationDialog extends StatefulWidget {
  const LatencyCalibrationDialog({super.key});

  static const String prefKey = 'audio_latency_offset_ms';

  @override
  State<LatencyCalibrationDialog> createState() => _LatencyCalibrationDialogState();
}

class _LatencyCalibrationDialogState extends State<LatencyCalibrationDialog> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _metronomeTimer;
  
  bool _isCalibrating = false;
  bool _isFlashing = false;
  
  int _beatCount = 0;
  final int _totalBeats = 8;
  final List<int> _offsets = [];
  
  DateTime? _lastBeatTime;

  @override
  void dispose() {
    _metronomeTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _startCalibration() {
    setState(() {
      _isCalibrating = true;
      _beatCount = 0;
      _offsets.clear();
    });
    HapticFeedback.mediumImpact();
    LogService.addEvent('LATENCY_CAL_START', {});

    // Toca o primeiro som após 1 segundo e depois a cada 800ms
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_isCalibrating) return;
      _playBeat();
      _metronomeTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        _beatCount++;
        if (_beatCount >= _totalBeats) {
          _finishCalibration();
        } else {
          _playBeat();
        }
      });
    });
  }

  Future<void> _playBeat() async {
    _lastBeatTime = DateTime.now();
    
    // Feedback visual
    setState(() => _isFlashing = true);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _isFlashing = false);
    });

    // Toca o som de referência (vamos usar o kick por ser seco e curto)
    try {
      await _audioPlayer.play(AssetSource('audio/kick.ogg'));
    } catch (e) {
      // Fallback se o áudio falhar
      SystemSound.play(SystemSoundType.click);
    }
  }

  void _handleTap() {
    if (!_isCalibrating || _lastBeatTime == null) return;
    
    final now = DateTime.now();
    final difference = now.difference(_lastBeatTime!).inMilliseconds;
    
    // Só consideramos toques que aconteceram próximos ao som (evita cliques aleatórios)
    if (difference < 500) {
      setState(() {
        _offsets.add(difference);
      });
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _finishCalibration() async {
    _metronomeTimer?.cancel();
    
    if (_offsets.isEmpty) {
      setState(() => _isCalibrating = false);
      return;
    }

    // Calcula a média, descartando o maior e o menor valor (outliers)
    _offsets.sort();
    final validOffsets = _offsets.length > 2 
        ? _offsets.sublist(1, _offsets.length - 1) 
        : _offsets;
    
    final int averageOffset = validOffsets.reduce((a, b) => a + b) ~/ validOffsets.length;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(LatencyCalibrationDialog.prefKey, averageOffset);
      
      LogService.addEvent('LATENCY_CAL_SAVED', {'offset_ms': averageOffset});
      
      if (mounted) {
        Navigator.pop(context, averageOffset);
      }
    } catch (e) {
      LogService.addEvent('LATENCY_CAL_ERROR', {'error': e.toString()});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Calibração de Latência'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Bata no círculo no exato momento em que ouvir o som.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          
          GestureDetector(
            onTap: _handleTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isFlashing 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: _isFlashing 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.outline,
                  width: 4,
                ),
                boxShadow: _isFlashing ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 10,
                  )
                ] : [],
              ),
              child: Center(
                child: Icon(
                  Icons.touch_app,
                  size: 48,
                  color: _isFlashing ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          if (_isCalibrating)
            Text(
              'Amostras: ${_offsets.length} / $_totalBeats',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            )
          else
            const SizedBox(height: 24), // Mantém o layout estável
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (!_isCalibrating)
          FilledButton(
            onPressed: _startCalibration,
            child: const Text('Iniciar'),
          ),
      ],
    );
  }
}