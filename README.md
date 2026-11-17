# 🥁 Mirandatune 🎸

Afinador offline e open-source para instrumentos de cordas e bateria (motor nativo configurado para Android).

## 📱 Sobre o Projeto

O Mirandatune foi desenvolvido com foco em processamento local e uma experiência de usuário (UX) direta. O microfone é usado para analisar frequências; eventos e diagnósticos podem ser salvos localmente e exportados pelo usuário. Não há envio automático implementado pelo app.

### Principais Funcionalidades
- **Afinador de Cordas:** Suporte a Violão (Padrão e Drop D), Baixo, Ukulele e Violino. Utiliza o algoritmo YIN no motor nativo Android.
- **Afinador de Bateria:** Foco em Pitch Tuning para Bumbo, Caixa, Toms e Surdo, com análise FFT por faixa de frequência.
- **Equalização de Parafusos:** Guia visual para afinação por padrão cruzado (estrela) em 6 ou 8 parafusos.
- **Teste de sincronização:** Ferramenta experimental de toque e reprodução; o valor salvo ainda não compensa a captura do microfone.
- **Acessibilidade:** Suporte a leitores de tela (TalkBack) com widgets de semântica.

## 🛠️ Arquitetura Técnica

O projeto utiliza uma arquitetura de Monorepo Flutter:
- **App Mobile (`apps/mobile`):** Interface do usuário, navegação e captura de áudio via pacote `record`. Construído em Flutter.
- **Motor DSP (`packages/dsp` e `android/app/src/main/cpp`):** O "cérebro" do processamento de áudio. Escrito em **C++ Nativo** e acessado via **Dart FFI**. Implementa Transformada Rápida de Fourier (FFT) e o algoritmo YIN.

**Por que C++ Nativo?**
O motor Android usa C++ via Dart FFI para processar cordas e a tela principal de bateria. Precisão, latência e desempenho em aparelhos reais ainda precisam de medição reproduzível.

## 🚀 Como Compilar e Rodar

### Pré-requisitos
- Flutter SDK compatível com Dart 3.13.7 ou posterior dentro da série 3.x (exigência do pacote dsp)
- Android Studio com NDK e CMake instalados (para compilação do C++)

### Passos
1. Clone o repositório:
   ```bash
   git clone https://github.com/Marcoferrera/Mirandatune.git
   cd Mirandatune/apps/mobile
