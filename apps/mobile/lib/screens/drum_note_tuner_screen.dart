import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:dsp/dsp.dart'; 
import '../services/log_service.dart';
import '../services/native_dsp.dart'; 
import '../widgets/latency_calibration_dialog.dart';

const Map<String, double> drumReferenceFreqs = {
  'Bumbo': 65.0,   
  'Caixa': 190.0,  
  'Tom 1': 160.0,  
  'Tom 2': 130.0,  
  'Surdo': 95.0,   
};

const Map<String, String> drumAudioAssets = {
  'Bumbo': 'audio/kick.ogg',
  'Caixa': 'audio/snare.ogg',
  'Tom 1': 'audio/tom_high.ogg',
  'Tom 2': 'audio/tom_mid.ogg',
  'Surdo': 'audio/tom_low.ogg',
};

class DrumPainter extends CustomPainter {
  final bool isSelected;

  DrumPainter({required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final shellPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF2A2A2A), const Color(0xFF121212)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, shellPaint);

    final hoopPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFFE0E0E0), const Color(0xFF808080), const Color(0xFFE0E0E0), const Color(0xFF808080)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12;
    canvas.drawCircle(center, radius * 0.92, hoopPaint);

    final skinPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFF5E6D3), const Color(0xFFC8B898)],
        center: const Alignment(-0.3, -0.3),
        radius: 1.0,
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.86));
    canvas.drawCircle(center, radius * 0.86, skinPaint);

    final innerShadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.05
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radius * 0.84, innerShadowPaint);

    final highlightPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.4),
        radius: 0.5,
        colors: [Colors.white.withOpacity(0.3), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius * 0.8, highlightPaint);

    if (isSelected) {
      final selectionPaint = Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.08
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, radius * 0.96, selectionPaint);
    }
  }

  @override
  bool shouldRepaint(DrumPainter oldDelegate) => oldDelegate.isSelected != isSelected;
}

class DrumNoteTunerScreen extends StatefulWidget {
  final String? initialDrum;
  const DrumNoteTunerScreen({super.key, this.initialDrum});
  @override
  State<DrumNoteTunerScreen> createState() => _DrumNoteTunerScreenState();
}

class _DrumNoteTunerScreenState extends State<DrumNoteTunerScreen> {
  final _recorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  
  StreamSubscription? _sub;
  
  final List<String> _drumOrder = ['Caixa', 'Tom 1', 'Tom 2', 'Surdo', 'Bumbo'];
  late PageController _pageController;
  int _currentPage = 0;

  String _selectedDrum = 'Caixa';
  double? _customTargetHz; 
  
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isPlayingAudio = false;
  bool _wasListeningBeforeAudio = false;
  
  List<double> _audioAccumulator = [];
  
  double? _currentF0;
  String _displayNote = '--';
  String _status = 'Aguardando batida...';
  Color _statusColor = Colors.grey;
  
  DateTime _lastHitTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
    if (widget.initialDrum != null && _drumOrder.contains(widget.initialDrum)) {
      _currentPage = _drumOrder.indexOf(widget.initialDrum!);
      _selectedDrum = widget.initialDrum!;
      _pageController = PageController(initialPage: _currentPage);
    }

    _audioPlayer.onPlayerComplete.listen((event) {
      if (!mounted) return;
      setState(() {
        _isPlayingAudio = false;
        _status = 'Aguardando batida...';
        _statusColor = Colors.grey;
      });
      if (_wasListeningBeforeAudio) {
        _wasListeningBeforeAudio = false;
        _startListening();
      }
    });

    _startListening();
  }

  // ===========================================================================
  // ✅ SUÍTE DE TESTES INTERNOS (GERADOR DE ONDAS SINTÉTICAS)
  // ===========================================================================
  void _runInternalTests() {
    final dsp = NativeDsp();
    final int sampleRate = 22050;
    final int length = 4096;
    List<String> report = [];

    // Teste 1: Caixa (190 Hz com ruído)
    List<double> caixaBuffer = List.generate(length, (i) {
      double t = i / sampleRate;
      return 0.5 * sin(2 * pi * 190 * t) + 
             0.2 * sin(2 * pi * 100 * t) + 
             0.1 * (Random().nextDouble() - 0.5);
    });
    double resCaixa = dsp.processarAudio(caixaBuffer, sampleRate, 0, 190.0);
    report.add('Caixa (190Hz): ${resCaixa.toStringAsFixed(2)} Hz ${(resCaixa - 190).abs() < 2 ? "✅" : "❌"}');

    // Teste 2: Bumbo (65 Hz com ruído)
    List<double> bumboBuffer = List.generate(length, (i) {
      double t = i / sampleRate;
      return 0.6 * sin(2 * pi * 65 * t) + 
             0.3 * sin(2 * pi * 130 * t) + 
             0.1 * (Random().nextDouble() - 0.5);
    });
    double resBumbo = dsp.processarAudio(bumboBuffer, sampleRate, 1, 65.0);
    report.add('Bumbo (65Hz): ${resBumbo.toStringAsFixed(2)} Hz ${(resBumbo - 65).abs() < 2 ? "✅" : "❌"}');

    // Teste 3: Tom 1 (160 Hz)
    List<double> tomBuffer = List.generate(length, (i) {
      double t = i / sampleRate;
      return 0.7 * sin(2 * pi * 160 * t) + 0.1 * (Random().nextDouble() - 0.5);
    });
    double resTom = dsp.processarAudio(tomBuffer, sampleRate, 2, 160.0);
    report.add('Tom 1 (160Hz): ${resTom.toStringAsFixed(2)} Hz ${(resTom - 160).abs() < 2 ? "✅" : "❌"}');

    // Exibe o resultado
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('🧪 Testes Internos DSP (C++)', style: TextStyle(color: Colors.white)),
        content: Text(
          report.join('\n\n'),
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _startListening() async {
    if (!await _recorder.hasPermission()) return;
    
    setState(() {
      _isListening = true;
      _status = 'Aguardando batida...';
      _statusColor = Colors.grey;
      _audioAccumulator.clear();
      _isProcessing = false;
    });

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 22050,
      numChannels: 1,
      echoCancel: false,
      noiseSuppress: false,
    ));

    _sub = stream.listen((data) {
      if (!_isListening || _isProcessing || _isPlayingAudio) return;

      for (int i = 0; i < data.length; i += 2) {
        int low = data[i];
        int high = data[i + 1];
        int sampleInt = (high << 8) | low;
        if (sampleInt >= 32768) sampleInt -= 65536;
        _audioAccumulator.add(sampleInt / 32768.0);
      }

      int targetSamples = _selectedDrum == 'Bumbo' ? 8192 : 4096;

      if (_audioAccumulator.length >= targetSamples) {
        double sumSquares = 0;
        for (double v in _audioAccumulator) sumSquares += v * v;
        final rms = sqrt(sumSquares / _audioAccumulator.length);

        if (rms > 0.02 && DateTime.now().difference(_lastHitTime).inMilliseconds > 600) {
          _lastHitTime = DateTime.now();
          
          final bufferToProcess = List<double>.from(_audioAccumulator);
          _audioAccumulator.clear(); 
          
          _processHit(bufferToProcess);
        } else if (rms < 0.01) {
          _audioAccumulator.clear();
        } else {
          _audioAccumulator.removeRange(0, targetSamples ~/ 2);
        }
      }
    });
  }

  Future<void> _processHit(List<double> buffer) async {
    _isProcessing = true;
    
    setState(() {
      _status = 'Analisando (C++)...';
      _statusColor = Colors.blueAccent;
    });

    try {
      int drumTypeInt = 0; 
      if (_selectedDrum == 'Bumbo') drumTypeInt = 1;
      if (_selectedDrum == 'Tom 1') drumTypeInt = 2;
      if (_selectedDrum == 'Tom 2') drumTypeInt = 3;
      if (_selectedDrum == 'Surdo') drumTypeInt = 4;

      double targetHz = _customTargetHz ?? drumReferenceFreqs[_selectedDrum]!;

      final dsp = NativeDsp();
      double f0 = dsp.processarAudio(buffer, 22050, drumTypeInt, targetHz);
      
      if (!mounted) return;

      if (f0 <= 0) {
        setState(() {
          _status = 'Aguardando batida...';
          _statusColor = Colors.grey;
        });
        return;
      }

      final noteResult = NoteConverter.frequencyToNote(f0);
      String note = '${noteResult.note}${noteResult.octave}';
      
      double diff = (f0 - targetHz).abs();
      
      Color color;
      String status;
      if (diff <= 2.0) {
        color = Colors.greenAccent; 
        status = 'AFINADO';
      } else if (diff <= 5.0) {
        color = Colors.amberAccent; 
        status = 'QUASE LÁ';
      } else {
        color = Colors.redAccent;   
        status = 'DESAFINADO';
      }

      setState(() {
        _currentF0 = f0;
        _displayNote = note;
        _status = status;
        _statusColor = color;
      });
    } catch (e) {
      print('❌ ERRO C++: $e');
      if (mounted) {
        setState(() {
          _status = 'Erro na ponte C++';
          _statusColor = Colors.red;
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _playReferenceAudio() async {
    if (_isPlayingAudio) {
      await _audioPlayer.stop();
      return;
    }

    if (_isListening) {
      _wasListeningBeforeAudio = true;
      await _sub?.cancel();
      await _recorder.stop();
      setState(() {
        _isListening = false;
        _status = 'Tocando Referência...';
        _statusColor = Colors.amber;
      });
    } else {
      _wasListeningBeforeAudio = false;
      setState(() {
        _status = 'Tocando Referência...';
        _statusColor = Colors.amber;
      });
    }

    setState(() {
      _isPlayingAudio = true;
    });

    final path = drumAudioAssets[_selectedDrum] ?? 'audio/snare.ogg';
    await _audioPlayer.play(AssetSource(path));
  }

  void _onPageChanged(int index) async {
    if (_isListening) {
      await _sub?.cancel();
      await _recorder.stop();
    }
    if (_isPlayingAudio) {
      await _audioPlayer.stop();
    }

    setState(() {
      _currentPage = index;
      _selectedDrum = _drumOrder[index];
      _customTargetHz = null; 
      _status = 'Aguardando batida...';
      _statusColor = Colors.grey;
      _currentF0 = null;
      _displayNote = '--';
      _audioAccumulator.clear();
      _isPlayingAudio = false;
      _isListening = false;
    });
    _startListening();
  }

  void _openTargetDialog() {
    final presetTarget = drumReferenceFreqs[_selectedDrum]!;
    double tempTarget = _customTargetHz ?? presetTarget;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('Referência para $_selectedDrum', style: const TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${tempTarget.toStringAsFixed(1)} Hz', style: const TextStyle(fontSize: 24, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  Slider(
                    value: tempTarget,
                    min: 40,
                    max: 300,
                    divisions: 260,
                    activeColor: Colors.blueAccent,
                    onChanged: (val) => setModalState(() => tempTarget = val),
                  ),
                ],
              );
            }
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _customTargetHz = null);
                Navigator.pop(context);
              },
              child: const Text('Usar Áudio', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _customTargetHz = tempTarget);
                Navigator.pop(context);
              },
              child: const Text('Aplicar'),
            ),
          ],
        );
      }
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildDrum(String name, double size) {
    bool isSelected = _selectedDrum == name;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: DrumPainter(isSelected: isSelected),
          ),
          Center(
            child: Text(
              name,
              style: TextStyle(
                fontSize: size * 0.16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double targetHz = _customTargetHz ?? drumReferenceFreqs[_selectedDrum]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Afinar Tambor', style: TextStyle(fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // ✅ BOTÃO DE TESTES INTERNOS
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.grey),
            tooltip: 'Testes Internos DSP',
            onPressed: _runInternalTests,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              height: 220,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: const PageScrollPhysics(),
                itemCount: _drumOrder.length,
                itemBuilder: (context, index) {
                  final name = _drumOrder[index];
                  return Center(child: _buildDrum(name, 200.0));
                },
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_drumOrder.length, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 12 : 8,
                  height: _currentPage == index ? 12 : 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index ? Colors.blueAccent : Colors.grey,
                  ),
                );
              }),
            ),

            const SizedBox(height: 10),

            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentF0 != null ? '${_currentF0!.toStringAsFixed(1)} Hz' : '-- Hz',
                  style: TextStyle(
                    fontSize: 52, 
                    fontWeight: FontWeight.bold, 
                    color: _currentF0 != null ? _statusColor : Colors.grey, 
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_displayNote, style: const TextStyle(fontSize: 18, color: Colors.grey)),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: _openTargetDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[800]!),
                        ),
                        child: Text(
                          'Ref: ${targetHz.toStringAsFixed(0)} Hz',
                          style: const TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            TextButton.icon(
              onPressed: _playReferenceAudio,
              icon: Icon(
                _isPlayingAudio ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                color: _isPlayingAudio ? Colors.amber : Colors.blueAccent,
              ),
              label: Text(
                _isPlayingAudio ? 'Parar Áudio' : 'Ouvir Referência',
                style: TextStyle(
                  color: _isPlayingAudio ? Colors.amber : Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            Column(
              children: [
                SizedBox(
                  width: 280, height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _statusColor == Colors.grey 
                          ? const Color(0xFF1E1E1E) 
                          : _statusColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      elevation: 0,
                      side: BorderSide(color: _statusColor == Colors.grey ? Colors.grey[800]! : Colors.transparent, width: 2),
                    ),
                    onPressed: null, 
                    child: Text(
                      _status,
                      style: TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        color: _statusColor == Colors.grey ? Colors.grey : Colors.black,
                      ),
                    ),
                  ),
                ),
                
                TextButton(
                  onPressed: () async {
                    LogService.addEvent('OPEN_LATENCY_CALIBRATION', {});
                    await showDialog(
                      context: context,
                      builder: (context) => const LatencyCalibrationDialog(),
                    );
                  },
                  child: const Text(
                    '⚙️ Calibrar latência',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}