import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:dsp/dsp.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NOVO: Para a Latência
import '../services/log_service.dart';
import '../widgets/latency_calibration_dialog.dart';

const Map<String, Map<String, double>> drumPresets = {
  'Bumbo':  {'target': 70.0,  'min': 45.0,  'max': 105.0},
  'Caixa':  {'target': 190.0, 'min': 150.0, 'max': 250.0},
  'Tom 1':  {'target': 160.0, 'min': 115.0, 'max': 210.0},
  'Tom 2':  {'target': 130.0, 'min': 95.0,  'max': 175.0},
  'Surdo':  {'target': 95.0,  'min': 60.0,  'max': 140.0},
};

const Map<String, String> drumAudioAssets = {
  'Bumbo': 'audio/kick.ogg',
  'Caixa': 'audio/snare.ogg',
  'Tom 1': 'audio/tom_high.ogg',
  'Tom 2': 'audio/tom_mid.ogg',
  'Surdo': 'audio/tom_low.ogg',
};

// ====== PAINTER REALISTA ======
class DrumPainter extends CustomPainter {
  final bool isResonantHead;
  final bool isKick;
  final bool isSelected;

  DrumPainter({required this.isResonantHead, required this.isKick, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center + const Offset(2, 4), radius * 0.95, shadowPaint);

    final shellPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          isKick ? const Color(0xFF2A2218) : const Color(0xFF1A1A1A),
          isKick ? const Color(0xFF0D0A07) : const Color(0xFF050505),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, shellPaint);

    final hoopColor1 = isResonantHead ? const Color(0xFFF9E596) : const Color(0xFFE0E0E0);
    final hoopColor2 = isResonantHead ? const Color(0xFFB5872A) : const Color(0xFF808080);
    final hoopPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [hoopColor1, hoopColor2, hoopColor1, hoopColor2],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12;
    canvas.drawCircle(center, radius * 0.92, hoopPaint);

    final skinColorCenter = isResonantHead 
        ? const Color(0xFFFDF7F0) 
        : (isKick ? const Color(0xFF6E5F4D) : const Color(0xFFF5E6D3));
    final skinColorEdge = isResonantHead 
        ? const Color(0xFFD4C4A8) 
        : (isKick ? const Color(0xFF2A2218) : const Color(0xFFC8B898));

    final skinPaint = Paint()
      ..shader = RadialGradient(
        colors: [skinColorCenter, skinColorEdge],
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
  bool shouldRepaint(DrumPainter oldDelegate) {
    return oldDelegate.isResonantHead != isResonantHead ||
           oldDelegate.isSelected != isSelected ||
           oldDelegate.isKick != isKick;
  }
}

// ====== TELA PRINCIPAL ======
class DrumNoteTunerScreen extends StatefulWidget {
  final String? initialDrum;
  const DrumNoteTunerScreen({super.key, this.initialDrum});
  @override
  State<DrumNoteTunerScreen> createState() => _DrumNoteTunerScreenState();
}

class _DrumNoteTunerScreenState extends State<DrumNoteTunerScreen> with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  StreamSubscription? _sub;
  
  final List<String> _drumOrder = ['Caixa', 'Tom 1', 'Tom 2', 'Surdo', 'Bumbo'];
  late PageController _pageController;
  int _currentPage = 0;

  String _selectedDrum = 'Caixa';
  String _mode = 'Resposta'; 
  
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  double? _refF0;
  double? _refRtf;

  bool _isListening = false;
  bool _isPlayingAudio = false;
  bool _wasListeningBeforeAudio = false;
  List<double> _audioAccumulator = [];
  List<double> _stableReadings = [];
  
  double? _currentF0;
  double? _currentF1;
  double? _currentRtf;
  String? _currentNote;
  String _status = 'Aperte Ativar Mic';
  Color _statusColor = Colors.grey;
  Color _freqColor = Colors.grey;
  bool _isAfinado = false;

  bool _jaVibrouNestaBatida = false; 
  
  // Variável para guardar a latência
  int _latencyOffsetMs = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
    if (widget.initialDrum != null && _drumOrder.contains(widget.initialDrum)) {
      _currentPage = _drumOrder.indexOf(widget.initialDrum!);
      _selectedDrum = widget.initialDrum!;
      _pageController = PageController(initialPage: _currentPage);
    }
    
    _flipController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 450),
      value: 1.0, 
    );
    _flipAnimation = Tween<double>(begin: 0.0, end: pi).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOutCubic)
    );

    _audioPlayer.onPlayerComplete.listen((event) {
      if (!mounted) return;
      setState(() {
        _isPlayingAudio = false;
        if (_wasListeningBeforeAudio) {
          _wasListeningBeforeAudio = false;
          _start(); 
        } else {
          _status = 'Aperte Ativar Mic';
          _statusColor = Colors.grey;
        }
      });
    });

    _loadLatencyOffset(); // Lê a latência calibrada
  }

  Future<void> _loadLatencyOffset() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _latencyOffsetMs = prefs.getInt(LatencyCalibrationDialog.prefKey) ?? 0;
    });
    LogService.addEvent('LATENCY_LOADED', {'offset_ms': _latencyOffsetMs});
  }

  void _onPageChanged(int index) async {
    if (_isListening) await _stop();
    if (_isPlayingAudio) {
      await _audioPlayer.stop();
      _isPlayingAudio = false;
      _wasListeningBeforeAudio = false;
    }
    
    setState(() {
      _currentPage = index;
      _selectedDrum = _drumOrder[index];
      _stableReadings.clear();
      _isAfinado = false;
      _jaVibrouNestaBatida = false;
      _status = 'Aperte Ativar Mic';
      _statusColor = Colors.grey;
    });
    LogService.addEvent('DRUM_SELECT', {'drum': _selectedDrum});
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
        _isAfinado = false;
      });
    } else {
      _wasListeningBeforeAudio = false;
    }

    setState(() {
      _isPlayingAudio = true;
    });

    final path = drumAudioAssets[_selectedDrum] ?? 'audio/snare.ogg';
    await _audioPlayer.play(AssetSource(path));
    LogService.addEvent('PLAY_REF_AUDIO', {'drum': _selectedDrum});
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) return;
    
    setState(() {
      _isListening = true;
      _isAfinado = false;
      _jaVibrouNestaBatida = false;
      _audioAccumulator.clear();
      _stableReadings.clear();
      _status = 'Ouvindo... Bata no centro do tambor!';
      _statusColor = Colors.blueAccent;
      _currentF0 = null;
      _currentNote = null;
    });

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 22050,
      numChannels: 1,
      echoCancel: false,
      noiseSuppress: false,
    ));

    int samplesCaptured = 0;
    int targetSamples = 33075;

    _sub = stream.listen((data) {
      for (int i = 0; i < data.length; i += 2) {
        int low = data[i];
        int high = data[i + 1];
        int sampleInt = (high << 8) | low;
        if (sampleInt >= 32768) sampleInt -= 65536;
        double rawSample = sampleInt / 32768.0;
        _audioAccumulator.add(rawSample);
        samplesCaptured++;
      }
      if (samplesCaptured >= targetSamples) {
        _processReading();
        samplesCaptured = 0;
      }
    });
  }

  void _processReading() {
    if (_audioAccumulator.length < 8192) return;
    double sumSquares = 0;
    for (double v in _audioAccumulator) sumSquares += v * v;
    final rms = sqrt(sumSquares / _audioAccumulator.length);
    
    if (rms < 0.4) {
      _audioAccumulator.clear();
      _jaVibrouNestaBatida = false; 
      return;
    }

    final result = DrumPitchDetector.detect(
      _audioAccumulator, 22050, drumType: _selectedDrum,
    );
    _audioAccumulator.clear();

    if (result.isSilent || result.f0 <= 0) return;
    _stableReadings.add(result.f0);
    if (_stableReadings.length > 3) _stableReadings.removeAt(0);
    if (_stableReadings.length < 2) return;

    double avgF0 = _stableReadings.reduce((a, b) => a + b) / _stableReadings.length;
    
    // ====== INTEGRAÇÃO DA LATÊNCIA ======
    // Aguarda o tempo calibrado antes de atualizar a tela
    Future.delayed(Duration(milliseconds: _latencyOffsetMs), () {
      if (!mounted) return;

      final noteResult = NoteConverter.frequencyToNote(avgF0);
      String noteStr = '${noteResult.note}${noteResult.octave}';

      final preset = drumPresets[_selectedDrum]!;
      bool atingiuAlvo = avgF0 >= preset['min']! && avgF0 <= preset['max']!;

      LogService.logReading(
        drumType: _selectedDrum,
        f0: avgF0,
        f1: result.f1 ?? 0.0,
        rtf: result.rtf ?? 0.0,
        rms: rms,
      );

      if (atingiuAlvo && !_jaVibrouNestaBatida) {
        HapticFeedback.mediumImpact();
        _jaVibrouNestaBatida = true;
      }

      setState(() {
        _currentF0 = avgF0;
        _currentF1 = result.f1;
        _currentRtf = result.rtf;
        _currentNote = noteStr;
        _freqColor = Colors.white;
        
        if (_mode == 'Resposta') {
          _isAfinado = atingiuAlvo;
          _status = atingiuAlvo ? '✓ CONFIRMADO' : 'Ajuste e salve a referência';
          _statusColor = atingiuAlvo ? Colors.greenAccent : Colors.amberAccent;
        } else {
          if (_refRtf != null && _currentRtf != null) {
            double diff = _currentRtf! - _refRtf!;
            if (diff.abs() <= 0.1) {
              _status = '✓ CONFIRMADO';
              _statusColor = Colors.greenAccent;
              _isAfinado = true;
            } else if (diff > 0.1) {
              _status = 'Mais tenso/aberto que a ref.';
              _statusColor = Colors.redAccent;
              _isAfinado = false;
            } else {
              _status = 'Mais controlado que a ref.';
              _statusColor = Colors.blueAccent;
              _isAfinado = false;
            }
          } else {
            _status = 'Salve uma ref. no modo Resposta primeiro';
            _statusColor = Colors.grey;
            _isAfinado = false;
          }
        }
      });
    });
  }

  void _saveReference() {
    if (_currentF0 == null) return;
    setState(() {
      _refF0 = _currentF0;
      _refRtf = _currentRtf;
      _status = '✓ Referência Salva (F0: ${_refF0!.toStringAsFixed(1)} Hz)';
      _statusColor = Colors.greenAccent;
      _isAfinado = false;
      _jaVibrouNestaBatida = false;
    });
    LogService.addEvent('REF_SAVED', {'f0': _refF0, 'rtf': _refRtf});
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    await _recorder.stop();
    setState(() {
      _isListening = false;
      _isAfinado = false;
      _jaVibrouNestaBatida = false;
      _status = 'Parado.';
      _statusColor = Colors.grey;
      _currentF0 = null;
      _currentNote = null;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    _flipController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildDrum(String name, double size) {
    bool isSelected = _selectedDrum == name;
    bool isKick = name == 'Bumbo';

    // Envolve o desenho num ExcludeSemantics (o visual não é lido pelo TalkBack)
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, child) {
          final angle = _flipAnimation.value;
          final isFront = angle < pi / 2;

          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(angle);

          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(size, size),
                    painter: DrumPainter(
                      isResonantHead: !isFront,
                      isKick: isKick,
                      isSelected: isSelected,
                    ),
                  ),
                  Transform(
                    transform: isFront ? Matrix4.identity() : Matrix4.rotationX(pi),
                    alignment: Alignment.center,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: size * 0.16,
                              fontWeight: FontWeight.bold,
                              color: isFront ? Colors.black87 : Colors.black54,
                            ),
                          ),
                          if (!isFront)
                            Icon(Icons.waves, color: const Color(0xFFD4A843), size: size * 0.18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDrumKit() {
    return SizedBox(
      height: 260,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const PageScrollPhysics(),
        itemCount: _drumOrder.length,
        itemBuilder: (context, index) {
          final name = _drumOrder[index];
          return Center(
            child: _buildDrum(name, 240.0),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String btnText;
    Color btnColor;
    VoidCallback? btnAction;

    if (_isPlayingAudio) {
      btnText = 'TOCANDO REFERÊNCIA...';
      btnColor = Colors.amber[700]!;
      btnAction = _playReferenceAudio;
    } else if (_isAfinado && _mode == 'Resposta') {
      btnText = 'SALVAR REFERÊNCIA';
      btnColor = Colors.green;
      btnAction = _saveReference;
    } else if (_isAfinado && _mode == 'Ataque') {
      btnText = 'AFINADO';
      btnColor = Colors.green;
      btnAction = _stop;
    } else if (_isListening) {
      btnText = 'OUVINDO...';
      btnColor = Colors.red[700]!;
      btnAction = _stop;
    } else {
      btnText = 'ATIVAR MIC';
      btnColor = Colors.red[700]!;
      btnAction = _start;
    }

    final preset = drumPresets[_selectedDrum]!;
    final targetHz = preset['target']!.toStringAsFixed(0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Afinar Tambor', style: TextStyle(fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Resposta', label: Text('Resposta', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'Ataque', label: Text('Ataque', style: TextStyle(fontSize: 12))),
              ],
              selected: {_mode},
              onSelectionChanged: (newSelection) async {
                if (_isListening) await _stop();
                if (_isPlayingAudio) {
                  await _audioPlayer.stop();
                  setState(() {
                    _isPlayingAudio = false;
                    _wasListeningBeforeAudio = false;
                  });
                }
                
                setState(() { 
                  _mode = newSelection.first; 
                });
                if (_mode == 'Resposta') {
                  _flipController.forward();
                } else {
                  _flipController.reverse();
                }
                LogService.addEvent('MODE_CHANGE', {'mode': _mode});
              },
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),

            Flexible(child: _buildDrumKit()),

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

            // ====== ACESSIBILIDADE (A11y) NAS INFORMAÇÕES ======
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: _currentNote != null 
                        ? 'Nota $_currentNote, ${_currentF0!.toStringAsFixed(1)} Hertz' 
                        : 'Aguardando batida',
                    child: Column(
                      children: [
                        Text(
                          _currentNote ?? '--',
                          style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: _freqColor),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentF0 != null ? 'F0: ${_currentF0!.toStringAsFixed(1)} Hz' : 'F0: -- Hz',
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                            if (_currentRtf != null) ...[
                              const SizedBox(width: 10),
                              Text(
                                'RTF: ${_currentRtf!.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 14, 
                                  fontWeight: FontWeight.bold,
                                  color: _currentRtf! > 1.6 ? Colors.redAccent : Colors.greenAccent,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  Semantics(
                    label: _status, // O leitor de tela anuncia o status
                    child: Column(
                      children: [
                        if (_isPlayingAudio)
                          Text(
                            '🔊 Referência: $targetHz Hz',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                          )
                        else
                          Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _statusColor),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_mode == 'Ataque')
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: TextButton.icon(
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
              ),

            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: 250, height: 50,
                child: Semantics(
                  button: true,
                  label: btnText,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: btnColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    onPressed: btnAction,
                    child: Text(
                      btnText,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),

            TextButton(
              onPressed: () async {
                LogService.addEvent('OPEN_LATENCY_CALIBRATION', {});
                
                final result = await showDialog<int>(
                  context: context,
                  builder: (context) => const LatencyCalibrationDialog(),
                );

                if (result != null && mounted) {
                  _loadLatencyOffset(); // Recarrega a latência após calibrar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Latência calibrada com sucesso: $result ms'),
                      backgroundColor: Colors.green[700],
                    ),
                  );
                }
              },
              child: const Text(
                '⚙️ Calibrar latência',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}