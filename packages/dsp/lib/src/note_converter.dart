import 'dart:math';

class NoteResult {
  final String note; // Ex: "A", "C#"
  final int octave;  // Ex: 4
  final double cents; // Desvio: -50 a +50

  NoteResult(this.note, this.octave, this.cents);

  @override
  String toString() => '$note$octave (${cents.toStringAsFixed(1)} cents)';
}

class NoteConverter {
  /// Transforma a frequência (ex: 440Hz) no nome da nota (A4) e vê se está desafinado.
  static NoteResult frequencyToNote(double frequency, {double referenceA4 = 440.0}) {
    if (frequency <= 0) return NoteResult('', 0, 0);

    // 1. Descobrimos o número MIDI (no sistema MIDI, o A4 é o número 69)
    final double midiNote = 12 * (log(frequency / referenceA4) / ln2) + 69;
    final int roundedMidi = midiNote.round();

    // 2. Calculamos qual seria a frequência perfeita para essa nota
    final double exactFreq = referenceA4 * pow(2, (roundedMidi - 69) / 12);

    // 3. Calculamos o desvio em Cents (1200 cents = 1 oitava). 
    // Se der 0, está perfeitamente afinado.
    final double cents = 1200 * (log(frequency / exactFreq) / ln2);

    // 4. Descobrimos o nome e a oitava
    final int noteIndex = roundedMidi % 12;
    final int octave = (roundedMidi / 12).floor() - 1;
    
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

    return NoteResult(names[noteIndex], octave, cents);
  }
}