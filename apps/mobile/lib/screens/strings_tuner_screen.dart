import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Import para o compute
import 'package:record/record.dart';
import 'package:dsp/dsp.dart';
import '../services/log_service.dart';

const Map<String, List<String>> instrumentPresets = {
  'Cromático': [],
  'Violão (Padrão)': ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
  'Violão (Drop D)': ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'],
  'Baixo 4 (Padrão)': ['E1', 'A1', 'D2', 'G2'],
  'Baixo 4 (Drop D)': ['D1', 'A1', 'D2', 'G2'],
  'Ukulele': ['G4', 'C4', 'E4', 'A4'],
  'Violino': ['G3', 'D4', 'A4', 'E5'],
};

// ✅ A FUNÇÃO ISOLATE É OBRIGATÓRIA PARA NÃO TRAVAR A TELA
Map<String, dynamic> _isolateDetectPitch(Map<String, dynamic> params) {
  final List<double> buffer = params['buffer'];
  final int sampleRate = params['sampleRate'];
  final result = PitchDetector.detect(buffer, sampleRate);
  return {
    'isSilent': result.isSilent,
    'frequency': result.frequency,
    'confidence': result.confidence,
  };
}

class StringsTunerScreen extends StatefulWidget {
  const StringsTunerScreen({super.key});
  @override
  State<StringsTunerScreen> createState() => _StringsTunerScreenState();
}

class _StringsTunerScreenState extends State<StringsTunerScreen> with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  StreamSubscription? _sub;
  
  String _currentPreset = 'Violão (Padrão)';
  double _referenceA4 = 440.0;
  int _capotraste = 0;

  bool _isListening = false;
  bool _isProcessing = false;
  List<double> _audioAccumulator = [];

  final List<double> _freqHistory = [];
  final List<double> _centsHistory = [];

  double? _currentFreq;
  double _cents = 0.0;
  bool _isInTune = false;
  String _displayNote = '--';
  
  DateTime _lastHitTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startListening();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopListening();
    _recorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_isListening) _stopListening();
    } else if (state == AppLifecycleState.resumed) {
      if (!_isListening) _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!await _recorder.hasPermission()) return;
    
    setState(() {
      _isListening = true;
      _audioAccumulator.clear();
      _freqHistory.clear();
      _centsHistory.clear();
      _currentFreq = null;
      _displayNote = '--';
      _isInTune = false;
      _isProcessing = false;
    });

    LogService.addEvent('STRING_TUNER_START', {'preset': _currentPreset});

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 22050,
      numChannels: 1,
      echoCancel: false,
      noiseSuppress: false,
    ));

    _sub = stream.listen((data) {
      if (!_isListening) return;

      for (int i = 0; i < data.length; i += 2) {
        int low = data[i];
        int high = data[i + 1];
        int sampleInt = (high << 8) | low;
        if (sampleInt >= 32768) sampleInt -= 65536;
        _audioAccumulator.add(sampleInt / 32768.0);
      }

      // Se o buffer acumulou muito, processa
      if (_audioAccumulator.length >= 4096 && !_isProcessing) {
        double sumSquares = 0;
        for (double v in _audioAccumulator) sumSquares += v * v;
        final rms = sqrt(sumSquares / _audioAccumulator.length);

        // Se o som for alto o suficiente, processa
        if (rms > 0.05 && DateTime.now().difference(_lastHitTime).inMilliseconds > 800) {
          _lastHitTime = DateTime.now();
          
          final bufferToProcess = List<double>.from(_audioAccumulator);
          _audioAccumulator.clear(); // Limpa imediatamente após tirar a cópia
          
          _processHit(bufferToProcess);
        } else if (rms < 0.02) {
          _audioAccumulator.clear();
        } else {
          // Se estiver no meio do som, remove metade para não acumular infinitamente
          _audioAccumulator.removeRange(0, 2048);
        }
      }
    });
  }

  Future<void> _processHit(List<double> buffer) async {
    _isProcessing = true;

    try {
      // ✅ USA COMPUTE PARA NÃO TRAVAR A TELA
      final resultMap = await compute(_isolateDetectPitch, {
        'buffer': buffer,
        'sampleRate': 22050,
      });

      if (!mounted) return;

      if (resultMap['isSilent'] || resultMap['confidence'] < 0.1) {
        _isProcessing = false;
        return;
      }

      final frequency = resultMap['frequency'] as double;
      final noteResult = NoteConverter.frequencyToNote(frequency, referenceA4: _referenceA4);
      
      String finalNote = noteResult.note;
      int finalOctave = noteResult.octave;
      
      if (_capotraste > 0) {
         final transposedMidi = (12 * (log(frequency / _referenceA4) / ln2) + 69).round() - _capotraste;
         final tNoteIndex = transposedMidi % 12;
         finalOctave = (transposedMidi / 12).floor() - 1;
         const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
         finalNote = names[tNoteIndex];
      }
      
      String fullNote = '$finalNote$finalOctave';
      double cents = noteResult.cents;

      _freqHistory.add(frequency);
      _centsHistory.add(cents);
      if (_freqHistory.length > 3) {
        _freqHistory.removeAt(0);
        _centsHistory.removeAt(0);
      }

      double avgFreq = _freqHistory.reduce((a, b) => a + b) / _freqHistory.length;
      double avgCents = _centsHistory.reduce((a, b) => a + b) / _centsHistory.length;

      bool inTune = _isInTune ? avgCents.abs() <= 15.0 : avgCents.abs() <= 5.0;

      if (mounted) {
        setState(() {
          _currentFreq = avgFreq;
          _displayNote = fullNote;
          _cents = avgCents;
          _isInTune = inTune;
        });
      }
    } catch (e) {
      LogService.addEvent('AUDIO_PROCESS_ERROR', {'error': e.toString()});
    } finally {
      _isProcessing = false; // ✅ Garante que destrava sempre
    }
  }

  Future<void> _stopListening() async {
    await _sub?.cancel();
    await _recorder.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
        _currentFreq = null;
        _displayNote = '--';
        _isInTune = false;
        _isProcessing = false;
      });
    }
    LogService.addEvent('STRING_TUNER_STOP', {});
  }

  void _openSettings() {
    // ... (Mantém o modal de configurações como estava)
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20.0, right: 20.0, top: 20.0, 
                bottom: MediaQuery.of(context).viewInsets.bottom + 30.0
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Configurações', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Referência A4:', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        Text('${_referenceA4.toStringAsFixed(0)} Hz', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      ],
                    ),
                    Slider(value: _referenceA4, min: 410, max: 470, divisions: 60, activeColor: Colors.blueAccent, onChanged: (val) => setModalState(() => _referenceA4 = val)),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Capotraste:', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        Text(_capotraste == 0 ? 'Desligado' : '${_capotraste}ª casa', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      ],
                    ),
                    Slider(value: _capotraste.toDouble(), min: 0, max: 12, divisions: 12, activeColor: Colors.blueAccent, onChanged: (val) => setModalState(() => _capotraste = val.toInt())),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () {
                          setState(() {});
                          LogService.addEvent('STRING_SETTINGS_APPLIED', {'a4': _referenceA4, 'capo': _capotraste});
                          Navigator.pop(context);
                        },
                        child: const Text('Aplicar e Fechar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  Color get _statusColor {
    if (_currentFreq == null) return Colors.grey;
    if (_isInTune) return const Color(0xFF4CAF50); 
    if (_cents.abs() <= 15) return const Color(0xFFFFC107); 
    return const Color(0xFFF44336); 
  }

  @override
  Widget build(BuildContext context) {
    double needlePosition = _cents.clamp(-50.0, 50.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Afinar Cordas', style: TextStyle(fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: _openSettings, tooltip: 'Configurações')],
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[800]!)),
                child: DropdownButton<String>(
                  value: _currentPreset,
                  dropdownColor: const Color(0xFF1E1E1E),
                  isExpanded: true,
                  underline: const SizedBox(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  items: instrumentPresets.keys.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                  onChanged: (newValue) {
                    setState(() { _currentPreset = newValue!; });
                    LogService.addEvent('STRING_PRESET_CHANGED', {'preset': _currentPreset});
                  },
                ),
              ),
            ),

            Column(
              children: [
                Semantics(
                  label: _currentFreq != null ? 'Nota $_displayNote' : 'Aguardando som',
                  child: Text(
                    _displayNote,
                    style: TextStyle(fontSize: 100, fontWeight: FontWeight.w900, color: _statusColor, letterSpacing: -2),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                _buildCifraClubNeedle(_statusColor, needlePosition),

                const SizedBox(height: 16),
                
                Text(
                  _currentFreq == null 
                      ? 'Aguardando som...' 
                      : (_isInTune ? 'AFINADO' : 'DESAFINADO'),
                  style: TextStyle(
                    fontSize: 22, 
                    fontWeight: FontWeight.bold, 
                    color: _isInTune ? const Color(0xFF4CAF50) : Colors.grey[400]
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCifraClubNeedle(Color color, double cents) {
    double progress = (cents + 50) / 100;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(height: 4, width: double.infinity, decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(2))),
              Container(width: 2, height: 40, color: Colors.grey[600]),
              LayoutBuilder(
                builder: (context, constraints) {
                  final double maxWidth = constraints.maxWidth;
                  final double xPos = (progress * maxWidth) - 10; 
                  
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 80),
                        curve: Curves.easeOut,
                        left: xPos,
                        child: Container(
                          width: 20, height: 60,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [if (_isInTune) BoxShadow(color: color.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)]
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Grave', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text('Agudo', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}