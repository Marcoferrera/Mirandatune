# 🥁 Mirandatune 🎸

Afinador profissional, 100% offline e open-source para instrumentos de cordas e bateria.

## 📱 Sobre o Projeto

O Mirandatune foi desenvolvido com foco em privacidade absoluta, performance de estúdio e uma experiência de usuário (UX) limpa e direta. Nenhum dado é enviado para a internet, e o microfone é utilizado apenas em tempo real para a análise de frequências, sem salvar ou transmitir áudio bruto.

### Principais Funcionalidades
- **Afinador de Cordas:** Suporte a Violão (Padrão e Drop D), Baixo, Ukulele e Violino. Utiliza o algoritmo YIN para precisão cirúrgica.
- **Afinador de Bateria:** Foco em Pitch Tuning para Bumbo, Caixa, Toms e Surdo, com filtro Biquad passa-banda e FFT.
- **Equalização de Parafusos:** Guia visual para afinação por padrão cruzado (estrela) em 6 ou 8 parafusos.
- **Calibração de Latência:** Ferramenta nativa para ajustar o atraso entre o áudio captado e a resposta na tela.
- **Acessibilidade:** Suporte a leitores de tela (TalkBack) com widgets de semântica.

## 🛠️ Arquitetura Técnica

O projeto utiliza uma arquitetura de Monorepo Flutter:
- **App Mobile (`apps/mobile`):** Interface do usuário, navegação e captura de áudio via pacote `record`. Construído em Flutter.
- **Motor DSP (`packages/dsp` e `android/app/src/main/cpp`):** O "cérebro" do processamento de áudio. Escrito em **C++ Nativo** e acessado via **Dart FFI**. Implementa Transformada Rápida de Fourier (FFT), Filtro Passa-Banda (Biquad) e o algoritmo YIN.

**Por que C++ Nativo?**
Processar áudio em tempo real no Dart causa gargalos (ANR) e imprecisões. Ao portar o motor de DSP para C++, o app atinge a taxa de quadros necessária para atualizar a tela sem travar e garante precisão sub-Hertz (erro < 0.3 Hz validado em testes).

## 🚀 Como Compilar e Rodar

### Pré-requisitos
- Flutter SDK (versão 3.0+)
- Android Studio com NDK e CMake instalados (para compilação do C++)

### Passos
1. Clone o repositório:
   ```bash
   git clone https://github.com/Marcoferrera/Mirandatune.git
   cd Mirandatune/apps/mobile