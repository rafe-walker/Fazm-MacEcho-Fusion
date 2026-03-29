//
//  MLXASREngine.swift
//  Fazm — ASR via mlx-audio-swift (SenseVoice or Qwen3-ASR)
//
//  Ported from MacEcho's sencevoice/model.py.
//  Primary: SenseVoice (multi-lingual, emotion/event detection).
//  Fallback: Qwen3-ASR (if SenseVoice model isn't available).
//

import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

/// Which ASR model to use.
enum ASRModelType: String, Codable, Sendable {
    case senseVoice = "senseVoice"
    case qwen3ASR = "qwen3ASR"
}

/// Automatic Speech Recognition engine using MLX-native models.
/// Processes complete speech segments (from VAD) and returns text.
actor MLXASREngine {

    // MARK: - State

    private var senseVoiceModel: SenseVoiceModel?
    private var genericSTTModel: (any STTGenerationModel)?
    private let config: MLXVoiceEngineConfig.ASRConfig
    private var activeModelType: ASRModelType?
    private var isLoading = false
    private var isReady = false

    // MARK: - Init

    init(config: MLXVoiceEngineConfig.ASRConfig = .init()) {
        self.config = config
    }

    // MARK: - Model Loading

    /// Load the ASR model. Tries SenseVoice first, falls back to Qwen3-ASR.
    func loadModel() async throws {
        guard !isLoading && !isReady else { return }
        isLoading = true
        defer { isLoading = false }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Try SenseVoice first (preferred — matches MacEcho pipeline)
        if config.modelID.lowercased().contains("sensevoice") {
            do {
                log("[ASR] Loading SenseVoice: \(config.modelID)")
                let model = try await SenseVoiceModel.fromPretrained(config.modelID)
                self.senseVoiceModel = model
                self.activeModelType = .senseVoice
                isReady = true
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                log("[ASR] SenseVoice loaded in \(String(format: "%.2f", elapsed))s")
                return
            } catch {
                log("[ASR] SenseVoice load failed: \(error). Falling back to Qwen3-ASR.")
            }
        }

        // Fallback: Qwen3-ASR
        let fallbackID = "mlx-community/Qwen3-ASR-1.7B-bf16"
        log("[ASR] Loading Qwen3-ASR: \(fallbackID)")
        do {
            let model = try await Qwen3ASRModel.fromPretrained(fallbackID)
            self.genericSTTModel = model
            self.activeModelType = .qwen3ASR
            isReady = true
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            log("[ASR] Qwen3-ASR loaded in \(String(format: "%.2f", elapsed))s")
        } catch {
            log("[ASR] Qwen3-ASR also failed: \(error)")
            throw error
        }
    }

    /// Warm up the model with a short dummy input.
    func warmUp() async {
        guard isReady else { return }
        log("[ASR] Warming up \(activeModelType?.rawValue ?? "unknown")...")
        let silenceSamples = [Float](repeating: 0.0, count: 16_000)
        let audioArray = MLXArray(silenceSamples)

        switch activeModelType {
        case .senseVoice:
            if let model = senseVoiceModel {
                _ = model.generate(
                    audio: audioArray,
                    generationParameters: STTGenerateParameters()
                )
            }
        case .qwen3ASR:
            if let model = genericSTTModel {
                _ = model.generate(
                    audio: audioArray,
                    generationParameters: STTGenerateParameters()
                )
            }
        case nil:
            break
        }
        log("[ASR] Warm-up complete")
    }

    // MARK: - Transcription

    /// Transcribe a speech segment (raw Float32 PCM @ 16 kHz).
    func transcribe(audioSamples: [Float]) async throws -> ASRResult? {
        guard isReady else {
            log("[ASR] Model not ready, skipping transcription")
            return nil
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let audioArray = MLXArray(audioSamples)
        var text = ""
        var language: String?

        switch activeModelType {
        case .senseVoice:
            if let model = senseVoiceModel {
                let output = model.generate(
                    audio: audioArray,
                    generationParameters: STTGenerateParameters(
                        language: config.language == "auto" ? nil : config.language
                    )
                )
                text = output.text
                language = output.language
            }

        case .qwen3ASR:
            if let model = genericSTTModel {
                let output = model.generate(
                    audio: audioArray,
                    generationParameters: STTGenerateParameters(
                        language: config.language == "auto" ? nil : config.language
                    )
                )
                text = output.text
                language = output.language
            }

        case nil:
            return nil
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let audioDuration = Double(audioSamples.count) / 16_000.0

        log("[ASR] [\(activeModelType?.rawValue ?? "?")] Transcribed \(String(format: "%.1f", audioDuration))s → \(String(format: "%.3f", elapsed))s: \"\(text.prefix(80))\"")

        return ASRResult(
            text: text,
            language: language,
            confidence: 1.0,
            audioDuration: audioDuration,
            processingTime: elapsed,
            modelType: activeModelType ?? .senseVoice
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

// MARK: - Logging Helper

private func log(_ message: String) {
    NSLog("[MLXVoiceEngine] %@", message)
}
