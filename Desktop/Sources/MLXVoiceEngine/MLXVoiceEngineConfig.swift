//
//  MLXVoiceEngineConfig.swift
//  Fazm — MLX Voice Engine Configuration
//
//  Ported from MacEcho's MacEchoConfig (Pydantic) to native Swift.
//  All models run locally on Apple Silicon via MLX.
//

import Foundation

/// Central configuration for the MLX-based local voice pipeline.
/// Mirrors MacEcho's hierarchical config: env vars → JSON → defaults.
struct MLXVoiceEngineConfig: Codable, Sendable {

    // MARK: - VAD

    struct VADConfig: Codable, Sendable {
        /// Speech probability threshold (0–1). Higher = less sensitive.
        var threshold: Float = 0.5
        /// Sampling rate expected by VAD (must match audio input).
        var samplingRate: Int = 16_000
        /// Seconds of pre-speech audio to prepend to each segment.
        var paddingDuration: Float = 0.2
        /// Minimum speech duration (seconds) to accept a segment.
        var minSpeechDuration: Float = 0.1
        /// Silence duration (seconds) before finalizing speech end.
        var silenceDuration: Float = 0.8
        /// Frame duration in seconds (32 ms = MacEcho default).
        var frameDuration: Float = 0.032
        /// Computed frame size in samples.
        var frameSize: Int { Int(frameDuration * Float(samplingRate)) }  // 512 @ 16 kHz
    }

    // MARK: - ASR (SenseVoice via mlx-audio-swift)

    struct ASRConfig: Codable, Sendable {
        /// HuggingFace model ID for SenseVoice.
        var modelID: String = "mlx-community/SenseVoice-Small"
        /// Language hint: "auto", "en", "zh", "ja", "ko".
        var language: String = "auto"
        /// Apply inverse text normalization (dates, numbers, etc.).
        var useITN: Bool = true
    }

    // MARK: - LLM (Qwen via mlx-swift-lm)

    struct LLMConfig: Codable, Sendable {
        /// HuggingFace model ID for the instruction-tuned Qwen model.
        var modelID: String = "mlx-community/Qwen2.5-7B-Instruct-4bit"
        /// Maximum tokens to generate per response.
        var maxTokens: Int = 1000
        /// Sampling temperature.
        var temperature: Float = 0.7
        /// Top-p nucleus sampling.
        var topP: Float = 0.9
        /// Maximum conversation context rounds to keep.
        var maxContextRounds: Int = 10
        /// Approximate token budget before oldest turns are pruned.
        var contextWindowSize: Int = 4000
        /// System prompt prepended to every conversation.
        var systemPrompt: String = """
            You are Fazm, a helpful AI assistant running entirely on the user's Mac.
            You can control the operating system, open apps, run terminal commands,
            change system settings, automate browser tasks, and more.
            Be concise, precise, and action-oriented. Execute commands directly when possible.
            """
    }

    // MARK: - TTS (Qwen3-TTS via mlx-audio-swift)

    struct TTSConfig: Codable, Sendable {
        /// HuggingFace model ID for TTS.
        var modelID: String = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
        /// Voice style / speaker name (model-dependent).
        var voice: String? = nil
        /// Max tokens for audio generation.
        var maxTokens: Int = 1200
        /// TTS sampling temperature.
        var temperature: Float = 0.6
        /// Output sample rate (Hz). Qwen3-TTS default is typically 24 kHz.
        var sampleRate: Int = 24_000
        /// Whether to enable TTS output at all.
        var enabled: Bool = true
    }

    // MARK: - Audio I/O

    struct AudioConfig: Codable, Sendable {
        /// Recording sample rate (matches VAD & ASR expectations).
        var recordingSampleRate: Int = 16_000
        /// Playback sample rate (matches TTS output).
        var playbackSampleRate: Int = 24_000
        /// Channels (1 = mono).
        var channels: Int = 1
    }

    // MARK: - Pipeline

    struct PipelineConfig: Codable, Sendable {
        /// Use local MLX pipeline by default (false = fallback to ACP bridge / cloud).
        var useLocalPipeline: Bool = true
        /// Whether to speak the response aloud.
        var enableTTS: Bool = true
        /// Enable streaming LLM output (token-by-token).
        var enableStreaming: Bool = true
        /// Enable conversation context memory.
        var enableContext: Bool = true
        /// Warm up models on launch for faster first inference.
        var warmUpOnLaunch: Bool = true
    }

    // MARK: - Instance properties

    var vad = VADConfig()
    var asr = ASRConfig()
    var llm = LLMConfig()
    var tts = TTSConfig()
    var audio = AudioConfig()
    var pipeline = PipelineConfig()

    // MARK: - Persistence

    /// File URL for persisted config (in Application Support).
    static var configFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Fazm", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mlx-voice-engine.json")
    }

    /// Load from disk, falling back to defaults.
    static func load() -> MLXVoiceEngineConfig {
        guard let data = try? Data(contentsOf: configFileURL),
              let config = try? JSONDecoder().decode(MLXVoiceEngineConfig.self, from: data)
        else {
            return MLXVoiceEngineConfig()
        }
        return config
    }

    /// Persist to disk.
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Self.configFileURL, options: .atomic)
    }
}
