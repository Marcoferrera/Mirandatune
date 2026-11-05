import 'dart:async';
import 'dart:io'; // ✅ Para gravar arquivos
import 'dart:typed_data'; // ✅ Para montar o WAV
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart'; // ✅ Para achar a pasta
import 'package:dsp/dsp.dart'; 
import '../services/log_service.dart';
import '../services/native_dsp.dart'; 
import '../widgets/latency_calibration_dialog.dart';

const Map<String, double> drumReferenceFreqs = {
  'Bumbo': 65.0, 'Caixa': 190.0, 'Tom 1': 160.0, 'Tom 2': 130.0, 'Surdo': 95.0,
};

const Map<String, String> drumAudioAssets = {
  'Bumbo': 'audio/kick.ogg', 'Caixa': 'audio/snare.ogg',
  'Tom 1': 'audio/tom_high.ogg', 'Tom 2': 'audio/tom_mid.ogg', 'Surdo': 'audio/tom_low.ogg',
};

class DrumPainter extends CustomPainter {
  final bool isSelected;
  DrumPainter({required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final shellPaint = Paint()..shader = RadialGradient(colors: [const Color(0xFF2A2A2A), const Color(0xFF121212)]).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, shellPaint);
    final hoopPaint = Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFFE0E0E0), const Color(0xFF808080), const Color(0xFFE0E0E0), const Color(0xFF808080)]).createShader(Rect.fromCircle(center: center, radius: radius))..style = PaintingStyle.stroke..strokeWidth = radius * 0.12;
    canvas.drawCircle(center, radius * 0.92, hoopPaint);
    final skinPaint = Paint()..shader = RadialGradient(colors: [const Color(0xFFF5E6D3), const Color(0xFFC8B898)], center: const Alignment(-0.3, -0.3), radius: 1.0).createShader(Rect.fromCircle(center: center, radius: radius * 0.86));
    canvas.drawCircle(center, radius * 0.86, skinPaint);
    final innerShadowPaint = Paint()..color = Colors.black.withOpacity(0.25)..style = PaintingStyle.stroke..strokeWidth = radius * 0.05..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radius * 0.84, innerShadowPaint);
    final highlightPaint = Paint()..shader = RadialGradient(center: const Alignment(-0.4, -0.4), radius: 0.5, colors: [Colors.white.withOpacity(0.3), Colors.transparent]).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius * 0.8, highlightPaint);
    if (isSelected) {
      final selectionPaint = Paint()..color = Colors.blueAccent..style = PaintingStyle.stroke..strokeWidth = radius * 0.08..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
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
  int _wavCounter = 0;

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
      setState(() { _isPlayingAudio = false; _status = 'Aguardando batida...'; _statusColor = Colors.grey; });
      if (_wasListeningBeforeAudio) { _wasListeningBeforeAudio = false; _startListening(); }
    });
    _startListening();
  }

  // ✅ FUNÇÃO PARA GRAVAR WAV (Apenas em Debug)
  Future<void> _saveWav(List<double> buffer) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final wavDir = Directory('${dir.path}/mirandatune_debug');
      if (!await wavDir.exists()) await wavDir.create();
      
      _wavCounter++;
      final file = File('${wavDir.path}/hit_${_wavCounter.toString().padLeft(3, '0')}.wav');
      
      const int sampleRate = 22050;
      final int numSamples = buffer.length;
      final int dataSize = numSamples * 2; // 16-bit
      
      final header = ByteData(44);
      // RIFF
      header.setUint8(0, 0x52); header.setUint8(1, 0x49); header.setUint8(2, 0x46); header.setUint8(3, 0x46);
      header.setUint32(4, 36 + dataSize, Endian.little);
      // WAVE
      header.setUint8(8, 0x57); header.setUint8(9, 0x41); header.setUint8(10, 0x56); header.setUint8(11, 0x45);
      // fmt 
      header.setUint8(12, 0x66); header.setUint8(13, 0x6D); header.setUint8(14, 0x74); header.setUint8(15, 0x20);
      header.setUint32(16, 16, Endian.little); // Subchunk1Size
      header.setUint16(20, 1, Endian.little); // AudioFormat (PCM)
      header.setUint16(22, 1, Endian.little); // NumChannels
      header.setUint32(24, sampleRate, Endian.little); // SampleRate
      header.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
      header.setUint16(32, 2, Endian.little); // BlockAlign
      header.setUint16(34, 16, Endian.little); // BitsPerSample
      // data
      header.setUint8(36, 0x64); header.setUint8(37, 0x61); header.setUint8(38, 0x74); header.setUint8(39, 0x61);
      header.setUint32(40, dataSize, Endian.little);
      
      final pcmData = ByteData(dataSize);
      for (int i = 0; i < numSamples; i++) {
        final val = (buffer[i] * 32767).clamp(-32768, 32767).toInt();
        pcmData.setInt16(i * 2, val, Endian.little);
      }
      
      final bytes = Uint8List(44 + dataSize);
      bytes.setRange(0, 44, header.buffer.asUint8List());
      bytes.setRange(44, 44 + dataSize, pcmData.buffer.asUint8List());
      
      await file.writeAsBytes(bytes);
      debugPrint('MIRANDA_WAV,${file.path}');
    } catch (e) {
      debugPrint('MIRANDA_WAV_ERR,$e');
    }
  }

  Future<void> _startListening() async {
    if (!await _recorder.hasPermission()) return;
    setState(() { _isListening = true; _status = 'Aguardando batida...'; _statusColor = Colors.grey; _audioAccumulator.clear(); _isProcessing = false; });

    final recordConfig = RecordConfig(
      encoder: AudioEncoder.pcm16bits, sampleRate: 22050, numChannels: 1,
      echoCancel: false, noiseSuppress: false,
      androidConfig: const AndroidRecordConfig(audioSource: AndroidAudioSource.unprocessed),
    );

    final stream = await _recorder.startStream(recordConfig);
    _sub = stream.listen((data) {
      if (!_isListening || _isProcessing || _isPlayingAudio) return;
      for (int i = 0; i < data.length; i += 2) {
        int low = data[i]; int high = data[i + 1]; int sampleInt = (high << 8) | low;
        if (sampleInt >= 32768) sampleInt -= 65536;
        _audioAccumulator.add(sampleInt / 32768.0);
      }
      
      // Buffer maior para ter certeza de que a janela de 2048 amostras cabe após o onset
      int targetSamples = _selectedDrum == 'Bumbo' ? 8192 : 6144;

      if (_audioAccumulator.length >= targetSamples) {
        double sumSquares = 0;
        for (double v in _audioAccumulator) sumSquares += v * v;
        final rms = sqrt(sumSquares / _audioAccumulator.length);
        
        // Gatilho
        if (rms > 0.02 && DateTime.now().difference(_lastHitTime).inMilliseconds > 600) {
          _lastHitTime = DateTime.now();
          final bufferToProcess = List<double>.from(_audioAccumulator);
          _audioAccumulator.clear(); 
          
          // ✅ GRAVA WAV ANTES DE PROCESSAR (Apenas em Debug)
          if (kDebugMode) {
            _saveWav(bufferToProcess);
          }
          
          _processHit(bufferToProcess);
        } else if (rms < 0.01) { _audioAccumulator.clear(); } 
        else { _audioAccumulator.removeRange(0, targetSamples ~/ 2); }
      }
    });
  }

  Future<void> _processHit(List<double> buffer) async {
    _isProcessing = true;
    setState(() { _status = 'Analisando (C++)...'; _statusColor = Colors.blueAccent; });

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
      if (f0 <= 0) { setState(() { _status = 'Aguardando batida...'; _statusColor = Colors.grey; }); return; }

      final noteResult = NoteConverter.frequencyToNote(f0);
      String note = '${noteResult.note}${noteResult.octave}';
      double diff = (f0 - targetHz).abs();
      
      Color color; String status;
      if (diff <= 2.0) { color = Colors.greenAccent; status = 'AFINADO'; } 
      else if (diff <= 5.0) { color = Colors.amberAccent; status = 'QUASE LÁ'; } 
      else { color = Colors.redAccent; status = 'DESAFINADO'; }

      setState(() { _currentF0 = f0; _displayNote = note; _status = status; _statusColor = color; });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ ERRO C++: $e');
      if (mounted) setState(() { _status = 'Erro na ponte C++'; _statusColor = Colors.red; });
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _playReferenceAudio() async {
    if (_isPlayingAudio) { await _audioPlayer.stop(); return; }
    if (_isListening) {
      _wasListeningBeforeAudio = true; await _sub?.cancel(); await _recorder.stop();
      setState(() { _isListening = false; _status = 'Tocando Referência...'; _statusColor = Colors.amber; });
    } else {
      _wasListeningBeforeAudio = false;
      setState(() { _status = 'Tocando Referência...'; _statusColor = Colors.amber; });
    }
    setState(() { _isPlayingAudio = true; });
    final path = drumAudioAssets[_selectedDrum] ?? 'audio/snare.ogg';
    await _audioPlayer.play(AssetSource(path));
  }

  void _onPageChanged(int index) async {
    if (_isListening) { await _sub?.cancel(); await _recorder.stop(); }
    if (_isPlayingAudio) { await _audioPlayer.stop(); }
    setState(() {
      _currentPage = index; _selectedDrum = _drumOrder[index]; _customTargetHz = null;
      _status = 'Aguardando batida...'; _statusColor = Colors.grey; _currentF0 = null; _displayNote = '--';
      _audioAccumulator.clear(); _isPlayingAudio = false; _isListening = false;
    });
    _startListening();
  }

  void _openTargetDialog() {
    final presetTarget = drumReferenceFreqs[_selectedDrum]!;
    double tempTarget = _customTargetHz ?? presetTarget;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Referência para $_selectedDrum', style: const TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setModalState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${tempTarget.toStringAsFixed(1)} Hz', style: const TextStyle(fontSize: 24, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
              Slider(value: tempTarget, min: 40, max: 300, divisions: 260, activeColor: Colors.blueAccent, onChanged: (val) => setModalState(() => tempTarget = val)),
              if (_currentF0 != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() { _customTargetHz = _currentF0; tempTarget = _currentF0!; });
                    setModalState(() {});
                  },
                  icon: const Icon(Icons.save, color: Colors.greenAccent),
                  label: const Text('Salvar Medição Atual', style: TextStyle(color: Colors.greenAccent)),
                ),
            ],
          )
        ),
        actions: [
          TextButton(onPressed: () { setState(() => _customTargetHz = null); Navigator.pop(context); }, child: const Text('Usar Padrão', style: TextStyle(color: Colors.grey))),
          ElevatedButton(onPressed: () { setState(() => _customTargetHz = tempTarget); Navigator.pop(context); }, child: const Text('Aplicar')),
        ],
      )
    );
  }

  @override
  void dispose() { _sub?.cancel(); _recorder.dispose(); _audioPlayer.dispose(); _pageController.dispose(); super.dispose(); }

  Widget _buildDrum(String name, double size) {
    bool isSelected = _selectedDrum == name;
    return SizedBox(
      width: size, height: size,
      child: Stack(
        children: [
          CustomPaint(size: Size(size, size), painter: DrumPainter(isSelected: isSelected)),
          Center(child: Text(name, style: TextStyle(fontSize: size * 0.16, fontWeight: FontWeight.bold, color: Colors.black87))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double targetHz = _customTargetHz ?? drumReferenceFreqs[_selectedDrum]!;
    return Scaffold(
      appBar: AppBar(title: const Text('Afinar Tambor', style: TextStyle(fontSize: 18)), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              height: 220,
              child: PageView.builder(
                controller: _pageController, onPageChanged: _onPageChanged, physics: const PageScrollPhysics(),
                itemCount: _drumOrder.length,
                itemBuilder: (context, index) => Center(child: _buildDrum(_drumOrder[index], 200.0)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_drumOrder.length, (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == index ? 12 : 8, height: _currentPage == index ? 12 : 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _currentPage == index ? Colors.blueAccent : Colors.grey),
              )),
            ),
            const SizedBox(height: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_currentF0 != null ? '${_currentF0!.toStringAsFixed(1)} Hz' : '-- Hz', style: TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: _currentF0 != null ? _statusColor : Colors.grey)),
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
                        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[800]!)),
                        child: Text('Ref: ${targetHz.toStringAsFixed(0)} Hz', style: const TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _playReferenceAudio,
              icon: Icon(_isPlayingAudio ? Icons.stop_circle_outlined : Icons.play_circle_outline, color: _isPlayingAudio ? Colors.amber : Colors.blueAccent),
              label: Text(_isPlayingAudio ? 'Parar Áudio' : 'Ouvir Referência', style: TextStyle(color: _isPlayingAudio ? Colors.amber : Colors.blueAccent, fontWeight: FontWeight.bold)),
            ),
            Column(
              children: [
                SizedBox(
                  width: 280, height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _statusColor == Colors.grey ? const Color(0xFF1E1E1E) : _statusColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), elevation: 0,
                      side: BorderSide(color: _statusColor == Colors.grey ? Colors.grey[800]! : Colors.transparent, width: 2),
                    ),
                    onPressed: null, 
                    child: Text(_status, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _statusColor == Colors.grey ? Colors.grey : Colors.black)),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    LogService.addEvent('OPEN_LATENCY_CALIBRATION', {});
                    await showDialog(context: context, builder: (context) => const LatencyCalibrationDialog());
                  },
                  child: const Text('⚙️ Calibrar latência', style: TextStyle(color: Colors.grey, fontSize: 12)),
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