import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:dsp/dsp.dart';
import '../services/log_service.dart';

const Map<String, Map<String, double>> drumPresets = {
  'Bumbo':          {'target': 65.0,  'min': 50.0,  'max': 100.0},
  'Caixa':          {'target': 190.0, 'min': 150.0, 'max': 250.0},
  'Tom 1 (Agudo)':  {'target': 160.0, 'min': 120.0, 'max': 210.0},
  'Tom 2 (Médio)':  {'target': 130.0, 'min': 100.0, 'max': 170.0},
  'Surdo':          {'target': 90.0,  'min': 70.0,  'max': 130.0},
};

class LugEqualizerScreen extends StatefulWidget {
  const LugEqualizerScreen({super.key});
  @override
  State<LugEqualizerScreen> createState() => _LugEqualizerScreenState();
}

class _LugEqualizerScreenState extends State<LugEqualizerScreen> {
  final _recorder = AudioRecorder();
  StreamSubscription? _sub;
  
  int _numParafusos = 6;
  int _currentParafuso = 1;
  double? _referenceFreq;
  Map<int, double> _parafusoFrequencies = {};
  
  bool _isListening = false;
  List<double> _audioAccumulator = [];
  
  String _mode = 'Padrão';
  String _selectedDrum = 'Tom 1 (Agudo)';
  
  String? _validationMessage;
  Color _validationColor = Colors.white;
  double? _lastFreqRead;

  List<double> _tempFrequencies = [];
  int _hitsCaptured = 0;
  DateTime _lastHitTime = DateTime.now();

  String get _drumTypeForDetector {
    if (_selectedDrum.contains('Tom 1')) return 'Tom 1';
    if (_selectedDrum.contains('Tom 2')) return 'Tom 2';
    if (_selectedDrum.contains('Bumbo')) return 'Bumbo';
    if (_selectedDrum.contains('Caixa')) return 'Caixa';
    if (_selectedDrum.contains('Surdo')) return 'Surdo';
    return 'Tom 1';
  }

  List<int> get _sequenciaAperto {
    if (_numParafusos == 8) return [1, 5, 3, 7, 2, 6, 4, 8];
    return [1, 4, 2, 5, 3, 6];
  }

  @override
  void initState() {
    super.initState();
    LogService.addEvent('PARAFUSO_EQ_INIT', {'drum': _selectedDrum, 'mode': _mode});
  }

  // Função para o usuário selecionar um parafuso manualmente ao clicar no círculo
  void _selectParafuso(int index) {
    if (_isListening) return; // Não deixa trocar enquanto grava
    setState(() {
      _currentParafuso = index;
      _validationMessage = null;
      _lastFreqRead = _parafusoFrequencies[index];
    });
  }

  Future<void> _startListening() async {
    if (!await _recorder.hasPermission()) return;

    setState(() {
      _isListening = true;
      _audioAccumulator.clear();
      _tempFrequencies.clear();
      _hitsCaptured = 0;
      _validationMessage = 'Ouvindo... Bata 3 vezes perto do Parafuso $_currentParafuso';
      _validationColor = Colors.blueAccent;
      _lastFreqRead = null;
    });

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

      if (_audioAccumulator.length > 3000) {
        _processBlock();
      }
    });
  }

  void _processBlock() {
    if (DateTime.now().difference(_lastHitTime).inMilliseconds < 300) {
      _audioAccumulator.clear();
      return;
    }

    double sumSquares = 0;
    for (double v in _audioAccumulator) sumSquares += v * v;
    final rms = sqrt(sumSquares / _audioAccumulator.length);

    if (rms < 0.2) {
      _audioAccumulator.clear();
      return;
    }

    final result = DrumPitchDetector.detect(
      _audioAccumulator, 22050, drumType: _drumTypeForDetector,
    );
    _audioAccumulator.clear();

    if (result.isSilent || result.f0 <= 30 || result.f0 >= 400) return;

    _lastHitTime = DateTime.now();
    _tempFrequencies.add(result.f0);
    _hitsCaptured++;

    setState(() {
      _lastFreqRead = result.f0;
      _validationMessage = 'Boa! Faltam ${3 - _hitsCaptured} batida(s).';
    });

    if (_hitsCaptured >= 3) {
      _finishMeasurement();
    }
  }

  void _finishMeasurement() async {
    await _sub?.cancel();
    await _recorder.stop();
    
    setState(() { _isListening = false; });

    _tempFrequencies.sort();
    double freqFinal = _tempFrequencies[1]; // Mediana das 3 batidas
    _hitsCaptured = 0;
    _tempFrequencies.clear();

    setState(() { _lastFreqRead = freqFinal; });

    if (_currentParafuso == 1 && _referenceFreq == null) {
      if (_mode == 'Padrão') {
        final preset = drumPresets[_selectedDrum]!;
        if (freqFinal < preset['min']! || freqFinal > preset['max']!) {
          setState(() {
            _validationMessage = 'Fora do padrão. Ajuste o Parafuso 1 e tente novamente.';
            _validationColor = Colors.redAccent;
          });
          return;
        }
      }
      
      setState(() {
        _referenceFreq = freqFinal;
        _parafusoFrequencies[_currentParafuso] = freqFinal;
        _validationMessage = '✓ Referência travada!';
        _validationColor = Colors.greenAccent;
      });
      LogService.addEvent('PARAFUSO_REF_SAVED', {'drum': _selectedDrum, 'f0': freqFinal});
      
    } else {
      setState(() {
        _parafusoFrequencies[_currentParafuso] = freqFinal;
        _validationMessage = 'Medição concluída.';
        _validationColor = Colors.white;
      });
      LogService.addEvent('PARAFUSO_MEASURED', {'drum': _selectedDrum, 'parafuso': _currentParafuso, 'f0': freqFinal});
    }
  }

  void _nextParafuso() {
    setState(() {
      int currentIndex = _sequenciaAperto.indexOf(_currentParafuso);
      if (currentIndex < _sequenciaAperto.length - 1) {
        _currentParafuso = _sequenciaAperto[currentIndex + 1];
        _validationMessage = null;
        _lastFreqRead = _parafusoFrequencies[_currentParafuso];
      } else {
        LogService.addEvent('PARAFUSO_EQ_COMPLETE', {'drum': _selectedDrum});
      }
    });
  }

  double _getDeltaCents(int parafuso) {
    if (_referenceFreq == null || !_parafusoFrequencies.containsKey(parafuso)) return 0.0;
    return 1200 * (log(_parafusoFrequencies[parafuso]! / _referenceFreq!) / ln2);
  }

  Color _getColor(int parafuso) {
    if (!_parafusoFrequencies.containsKey(parafuso)) return Colors.grey;
    if (parafuso == 1 && _referenceFreq != null) return Colors.greenAccent;
    final delta = _getDeltaCents(parafuso).abs();
    if (delta <= 5) return const Color(0xFF4CAF50);
    if (delta <= 15) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  String _getTuningAdvice(int parafuso) {
    if (!_parafusoFrequencies.containsKey(parafuso) || _referenceFreq == null || parafuso == 1) return '';
    
    double delta = _getDeltaCents(parafuso);
    double absDelta = delta.abs();

    if (absDelta <= 5) return '✅ Perfeito!';
    
    String acao = delta < 0 ? 'Aperte' : 'Afrouxe';
    if (absDelta <= 15) return '🟡 $acao um pouco';
    return '🔴 $acao bastante';
  }

  void _reset() async {
    await _sub?.cancel();
    await _recorder.stop();
    setState(() {
      _referenceFreq = null;
      _parafusoFrequencies.clear();
      _currentParafuso = 1;
      _validationMessage = null;
      _hitsCaptured = 0;
      _tempFrequencies.clear();
      _isListening = false;
      _lastFreqRead = null;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool jaMedido = _parafusoFrequencies.containsKey(_currentParafuso);
    double deltaAtual = _getDeltaCents(_currentParafuso).abs();
    bool isAfinado = jaMedido && _currentParafuso != 1 && deltaAtual <= 5.0;
    bool isFinished = _parafusoFrequencies.length == _numParafusos;

    String buttonText;
    Color buttonColor;
    VoidCallback? buttonAction;

    if (isFinished) {
      buttonText = 'EQUALIZAÇÃO CONCLUÍDA 🎉';
      buttonColor = Colors.green;
      buttonAction = _reset;
    } else if (_isListening) {
      buttonText = 'OUVINDO... (${_hitsCaptured}/3)';
      buttonColor = Colors.red;
      buttonAction = () async { await _sub?.cancel(); await _recorder.stop(); setState(() => _isListening = false); };
    } else if (_currentParafuso == 1 && _referenceFreq == null) {
      buttonText = 'INICIAR LEITURA (REFERÊNCIA)';
      buttonColor = Colors.blueAccent;
      buttonAction = _startListening;
    } else if (isAfinado) {
      buttonText = 'PRÓXIMO SUGERIDO';
      buttonColor = Colors.green;
      buttonAction = _nextParafuso;
    } else {
      buttonText = 'MEDIR PARAFUSO $_currentParafuso';
      buttonColor = Colors.blueAccent;
      buttonAction = _startListening;
    }

    String advice = _getTuningAdvice(_currentParafuso);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalização de Parafusos', style: TextStyle(fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.redAccent),
            onPressed: _reset,
            tooltip: 'Redefinir Tudo',
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // CONTROLES DE TOPO
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Livre', label: Text('Livre', style: TextStyle(fontSize: 13))),
                        ButtonSegment(value: 'Padrão', label: Text('Padrão', style: TextStyle(fontSize: 13))),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() { _mode = newSelection.first; });
                        _reset();
                      },
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<int>(
                    value: _numParafusos,
                    dropdownColor: const Color(0xFF1E1E1E),
                    underline: const SizedBox(),
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    items: [6, 8].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                    onChanged: (val) {
                      setState(() { _numParafusos = val!; });
                      _reset();
                    },
                  )
                ],
              ),
            ),
            
            if (_mode == 'Padrão')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: DropdownButton<String>(
                  value: _selectedDrum,
                  dropdownColor: const Color(0xFF1E1E1E),
                  isExpanded: true,
                  style: const TextStyle(fontSize: 14),
                  items: drumPresets.keys.map((String key) => DropdownMenuItem(value: key, child: Text('$key'))).toList(),
                  onChanged: (val) {
                    setState(() { _selectedDrum = val!; });
                    _reset();
                  },
                ),
              ),

            // VISUALIZADOR CIRCULAR
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 300, height: 300,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 230, height: 230,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          border: Border.all(
                            color: _isListening ? Colors.blueAccent : Colors.grey[800]!, 
                            width: _isListening ? 4 : 2
                          )
                        ),
                      ),
                      
                      // CENTRO: Mostra a Referência e o último Hz lido
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_referenceFreq != null && _currentParafuso != 1)
                            Text('Ref: ${_referenceFreq!.toStringAsFixed(1)} Hz', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          
                          const SizedBox(height: 4),
                          if (_lastFreqRead != null)
                            Text('${_lastFreqRead!.toStringAsFixed(1)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white))
                          else
                            const Text('--', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.grey)),
                          
                          const Text('Hz', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          const SizedBox(height: 4),
                          
                          // Nome do parafuso com a cor
                          Text(
                            'Parafuso $_currentParafuso', 
                            style: TextStyle(
                              fontSize: 16, 
                              color: _getColor(_currentParafuso), 
                              fontWeight: FontWeight.bold
                            )
                          ),
                        ],
                      ),
                      
                      // CÍRCULO DE PARAFUSOS (CLICÁVEIS)
                      ...List.generate(_numParafusos, (index) {
                        final pNum = index + 1;
                        final angle = (pNum / _numParafusos) * 2 * pi - (pi / 2);
                        final x = cos(angle) * 125;
                        final y = sin(angle) * 125;
                        final color = _getColor(pNum);
                        
                        return Positioned(
                          left: 150 + x - 18, 
                          top: 150 + y - 18,
                          child: GestureDetector(
                            onTap: () => _selectParafuso(pNum), // PERMITE CLICAR NO PARAFUSO!
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle, color: color.withOpacity(0.2),
                                border: Border.all(color: color, width: 2),
                                boxShadow: [if (pNum == _currentParafuso && _isListening) BoxShadow(color: color, blurRadius: 10, spreadRadius: 2)]
                              ),
                              child: Center(child: Text('$pNum', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),

            // TEXTOS DE STATUS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Column(
                children: [
                  if (_validationMessage != null)
                    Text(
                      _validationMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _validationColor),
                    ),
                  if (jaMedido && _currentParafuso != 1) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Diferença: ${_getDeltaCents(_currentParafuso) > 0 ? "+" : ""}${_getDeltaCents(_currentParafuso).toStringAsFixed(1)} cents',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _getColor(_currentParafuso)),
                    ),
                    if (advice.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        advice,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _getColor(_currentParafuso)),
                      ),
                    ]
                  ]
                ],
              ),
            ),

            // BOTÕES DE AÇÃO
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              decoration: BoxDecoration(color: const Color(0xFF121212), border: Border(top: BorderSide(color: Colors.grey[800]!, width: 1))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity, height: 50, 
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor, 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: buttonAction,
                      child: Text(
                        buttonText, 
                        textAlign: TextAlign.center, 
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentParafuso != 1 && !_isListening && !isFinished && !jaMedido)
                        TextButton.icon(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: _nextParafuso, 
                          icon: const Icon(Icons.skip_next, color: Colors.grey, size: 18), 
                          label: const Text('Pular Sugestão', style: TextStyle(color: Colors.grey, fontSize: 12))
                        )
                      else
                        const SizedBox(width: 1),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}