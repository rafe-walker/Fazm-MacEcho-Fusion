//
//  MLXASREngine.swift
//  Fazm — ASR via mlx-audio-swift (Qwen3-ASR)
//
//  Ported from MacEcho's sencevoice/model.py.
//  Uses Qwen3-ASR (SenseVoice is not available in current mlx-audio-swift).
//

import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

/// Which ASR model to use.
enum ASRModelType: String, Codable, Sendable {
    case qwen3ASR = "qwen3ASR"
}

/// Automatic Speech Recognition engine using MLX-native models.
/// Processes complete speech segments (from VAD) and returns text.
actor MLXASREngine {

    // MARK: - State

    private var model: Qwen3ASRModel?
    private let config: MLXVoiceEngineConfig.ASRConfig
    private var activeModelType: ASRModelType?
    private var isLoading = false
    private var isReady = false

    // MARK: - Init

    init(config: MLXVoiceEngineConfig.ASRConfig = .init()) {
        self.config = config
    }

    // MARK: - Model Loading

    /// Load the ASR model (Qwen3-ASR).
    func loadModel() async throws {
        guard !isLoading && !isReady else { return }
        isLoading = true
        defer { isLoading = false }

        let startTime = CFAbsoluteTimeGetCurrent()

        let modelID = config.modelID.lowercased().contains("sensevoice")
            ? "mlx-community/Qwen3-ASR-1.7B-bf16"  // SenseVoice not available, use Qwen3-ASR
            : config.modelID

        mlxLog("[ASR] Loading Qwen3-ASR: \(modelID)")
        let loadedModel = try await Qwen3ASRModel.fromPretrained(modelID)
        self.model = loadedModel
        self.activeModelType = .qwen3ASR
        isReady = true

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        mlxLog("[ASR] Qwen3-ASR loaded in \(String(format: "%.2f", elapsed))s")
    }

    /// Warm up the model with a short dummy input.
    func warmUp() async {
        guard isReady, let model else { return }
        mlxLog("[ASR] Warming up Qwen3-ASR...")
        let silenceSamples = [Float](repeating: 0.0, count: 16_000)
        let audioArray = MLXArray(silenceSamples)
        _ = model.generate(
            audio: audioArray,
            generationParameters: STTGenerateParameters()
        )
        mlxLog("[ASR] Warm-up complete")
    }

    // MARK: - Transcription

    /// Transcribe a speech segment (raw Float32 PCM @ 16 kHz).
    func transcribe(audioSamples: [Float]) async throws -> ASRResult? {
        guard isReady, let model else {
            mlxLog("[ASR] Model not ready, skipping transcription")
            return nil
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let audioArray = MLXArray(audioSamples)

        let lang = (config.language == "auto") ? "English" : config.language
        let output = model.generate(
            audio: audioArray,
            generationParameters: STTGenerateParameters(language: lang)
        )
        let text = output.text
        let language = output.language

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let audioDuration = Double(audioSamples.count) / 16_000.0

        mlxLog("[ASR] Transcribed \(String(format: "%.1f", audioDuration))s → \(String(format: "%.3f", elapsed))s: \"\(text.prefix(80))\"")

        return ASRResult(
            text: text,
            language: language,
            confidence: 1.0,
            audioDuration: audioDuration,
            processingTime: elapsed,
            modelType: activeModelType ?? .qwen3ASR
        )
    }

    /// Which model is active.
    var currentModel: ASRModelType? { activeModelType }
}

// MARK: - ASR Result

struct ASRResult: Sendable {
    let text: String
    let language: String?
    let confidence: Double
    let audioDuration: Double
    let processingTime: Double
    let modelType: ASRModelType
}
