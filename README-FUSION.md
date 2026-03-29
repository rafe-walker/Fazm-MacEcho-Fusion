# Fazm + MacEcho Fusion — Native M3-Optimized Voice Overlay

A native Swift/SwiftUI macOS app that gives you **full voice control of your entire OS** using natural language, with ultra-low-latency local inference — all running on your M3 MacBook Pro via Apple MLX.

## What Is This?

This is a clean fork of [Fazm](https://github.com/m13v/fazm) with [MacEcho's](https://github.com/realtime-ai/mac-echo) optimized voice pipeline ported to native Swift using `mlx-swift` + `mlx-audio-swift`. No Python. No cloud. No latency.

### Pipeline Architecture

```
Microphone (CoreAudio @ 16 kHz)
    │
    ▼
┌──────────────────────────────┐
│  Silero VAD v5 (pure MLX)    │  32 ms frames, ~40 μs/frame
│  via speech-swift             │  Neural Engine accelerated
└──────────────────────────────┘
    │ speech segment
    ▼
┌──────────────────────────────┐
│  SenseVoice ASR              │  Multi-lingual, ~200 ms for 3s audio
│  via mlx-audio-swift          │  Fallback: Qwen3-ASR
└──────────────────────────────┘
    │ transcribed text
    ▼
┌──────────────────────────────┐
│  Qwen 2.5 7B Instruct 4-bit │  Streaming tokens, 20-50 tok/s
│  via mlx-swift-lm             │  Full conversation context
└──────────────────────────────┘
    │ streaming response
    ▼
┌──────────────────────────────┐
│  Qwen3-TTS                   │  Streaming audio, RTF < 0.3
│  via mlx-audio-swift          │  Sentence-level pipelining
└──────────────────────────────┘
    │ audio chunks
    ▼
  Speaker (AVAudioEngine)
```

### Performance Targets (M3 MacBook Pro)

| Metric | Target |
|--------|--------|
| First response latency | < 1 second |
| VAD frame latency | ~40 μs per 32 ms frame |
| ASR processing | ~200 ms for 3s audio |
| LLM generation | 20-50 tokens/second |
| TTS real-time factor | < 0.3 |
| Memory usage | ~6 GB (7B model) |

## Features (Inherited from Fazm)

Everything Fazm can do, plus local MLX voice:

- **Full OS Control**: Open apps, run terminal commands, change settings
- **Accessibility APIs**: Click UI elements, read screen content
- **AppleScript**: Automate any scriptable application
- **Browser Control**: Playwright-based web automation
- **Document Handling**: PDF, DOCX, XLSX via bundled skills
- **Google Workspace**: Docs, Sheets, Gmail integration
- **Workflow Learning**: Teaches itself from your patterns
- **Menubar Overlay**: Floating pill with hotkey trigger (Cmd+\)
- **Push-to-Talk**: Hold Option key for voice input
- **Privacy**: 100% local by default (no cloud calls)

## Quick Start

### 1. Pre-download Models (~5.5 GB, one time)

```bash
cd ~/Desktop/Fazm-MacEcho-Fusion
./setup-mlx-models.sh
```

### 2. Build and Run

```bash
./run.sh
```

This builds the Swift app, creates the app bundle, signs it, and launches.

### 3. Grant Permissions

On first launch, grant:
- **Microphone** — for voice input
- **Accessibility** — for OS control and hotkeys
- **Screen Recording** — for screenshot context

### 4. Use It

- **Cmd+\\** — Toggle the floating control bar
- **Hold Option** — Push-to-talk (speaks your command)
- **Double-tap Option** — Lock listening mode

Example commands:
- "Open Safari, search for the weather in Tokyo"
- "Dim the screen to 40%"
- "Create a new folder on the Desktop called Projects"
- "Read me the first paragraph of the open document"
- "Run `git status` in my current terminal"

## Architecture

### Two Pipeline Modes

**1. Full Local Pipeline** (default when models are loaded):
```
Voice → VAD → ASR → Qwen LLM → TTS → Speaker
```
Everything runs on-device. Sub-second response times.

**2. Transcription-Only Mode** (fallback to Claude):
```
Voice → VAD → ASR → [text feeds into Fazm's ACP Bridge → Claude]
```
Uses local ASR but sends text to Claude for complex reasoning.
Falls back automatically if LLM models aren't loaded.

### Key Files

```
Desktop/Sources/MLXVoiceEngine/
├── VoiceEngine.swift           # Main orchestrator (VAD → ASR → LLM → TTS)
├── VoiceEngineBridge.swift     # Bridges into Fazm's existing systems
├── SileroVAD.swift             # Pure-MLX Silero VAD v5 (speech-swift)
├── MLXASREngine.swift          # SenseVoice / Qwen3-ASR
├── MLXLLMEngine.swift          # Qwen 2.5 7B streaming generation
├── MLXTTSEngine.swift          # Qwen3-TTS streaming synthesis
├── LLMSentencizer.swift        # Real-time sentence splitting for TTS
├── MLXVoiceEngineConfig.swift  # Pipeline configuration
├── ModelDownloadManager.swift  # Model cache management
└── PushToTalkMLXExtension.swift # Integration documentation
```

### Dependencies Added

| Package | Purpose | Version |
|---------|---------|---------|
| mlx-swift | Core MLX framework | ≥ 0.30.6 |
| mlx-swift-lm | LLM loading (Qwen) | ≥ 2.30.3 |
| mlx-audio-swift | ASR + TTS models | ≥ 0.1.0 |
| speech-swift | Silero VAD v5 (pure MLX) | main |

### Models Used

| Component | Model | Size | Source |
|-----------|-------|------|--------|
| VAD | Silero VAD v5 | ~1.2 MB | Auto-downloaded |
| ASR | SenseVoice-Small | ~500 MB | mlx-community |
| ASR (fallback) | Qwen3-ASR-1.7B | ~1.7 GB | mlx-community |
| LLM | Qwen2.5-7B-Instruct-4bit | ~4.5 GB | mlx-community |
| TTS | Qwen3-TTS-12Hz-0.6B-8bit | ~400 MB | mlx-community |

## Configuration

Edit `~/Library/Application Support/Fazm/mlx-voice-engine.json`:

```json
{
  "pipeline": {
    "useLocalPipeline": true,
    "enableTTS": true,
    "enableStreaming": true,
    "warmUpOnLaunch": true
  },
  "llm": {
    "modelID": "mlx-community/Qwen2.5-7B-Instruct-4bit",
    "maxTokens": 1000,
    "temperature": 0.7
  },
  "vad": {
    "threshold": 0.5,
    "silenceDuration": 0.8,
    "frameDuration": 0.032
  }
}
```

## Manual Steps

### Code Signing

The app is signed with your local developer identity during `run.sh`.
For distribution, you'll need:
1. An Apple Developer account
2. Update the signing identity in `run.sh`
3. Notarize with `xcrun notarytool`

### Switching to 14B Model

If your M3 has 36+ GB RAM, edit the config:
```json
{
  "llm": {
    "modelID": "mlx-community/Qwen2.5-14B-Instruct-4bit"
  }
}
```
Then re-run `./setup-mlx-models.sh` and relaunch.

## Credits

- [Fazm](https://github.com/m13v/fazm) — The macOS AI agent with full OS control
- [MacEcho](https://github.com/realtime-ai/mac-echo) — Ultra-low-latency MLX voice pipeline
- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) — Native MLX audio models
- [speech-swift](https://github.com/soniqo/speech-swift) — Pure-MLX Silero VAD v5
- [MLX](https://github.com/ml-explore/mlx) — Apple's machine learning framework

## License

Same as Fazm's original license. MLX models are subject to their respective licenses (Apache 2.0, Qwen License).
