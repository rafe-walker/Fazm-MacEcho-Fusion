//
//  ModelDownloadManager.swift
//  Fazm — MLX Model Download & Cache Manager
//
//  Handles downloading MLX models from HuggingFace Hub and caching
//  them locally in ~/.cache/huggingface/. Provides progress tracking
//  for the UI to show download status.
//

import Combine
import Foundation

/// Manages model downloads and cache for the MLX voice pipeline.
@MainActor
final class ModelDownloadManager: ObservableObject {

    static let shared = ModelDownloadManager()

    // MARK: - State

    struct ModelInfo: Identifiable {
        let id: String  // HuggingFace model ID
        let name: String
        let estimatedSizeGB: Double
        var isDownloaded: Bool = false
        var downloadProgress: Double = 0.0  // 0.0 ... 1.0
    }

    @Published var models: [ModelInfo] = []
    @Published var isDownloading = false
    @Published var overallProgress: Double = 0.0

    // MARK: - Cache Path

    static var cacheDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    }

    // MARK: - Init

    private init() {
        refreshModelList()
    }

    /// Refresh the model list and check which are already cached.
    func refreshModelList() {
        let config = MLXVoiceEngineConfig.load()
        models = [
            ModelInfo(
                id: "silero-vad-v5",
                name: "Silero VAD v5",
                estimatedSizeGB: 0.002,  // ~1.2 MB
                isDownloaded: checkCached("silero-vad-v5")
            ),
            ModelInfo(
                id: config.asr.modelID,
                name: "SenseVoice ASR",
                estimatedSizeGB: 0.5,
                isDownloaded: checkCached(config.asr.modelID)
            ),
            ModelInfo(
                id: config.llm.modelID,
                name: "Qwen2.5-7B LLM",
                estimatedSizeGB: 4.5,
                isDownloaded: checkCached(config.llm.modelID)
            ),
            ModelInfo(
                id: config.tts.modelID,
                name: "Qwen3-TTS",
                estimatedSizeGB: 0.4,
                isDownloaded: checkCached(config.tts.modelID)
            ),
        ]
    }

    /// Check if a model is already in the HuggingFace cache.
    private func checkCached(_ modelID: String) -> Bool {
        // HuggingFace cache stores models in models--{org}--{repo} directories
        let sanitized = modelID.replacingOccurrences(of: "/", with: "--")
        let modelDir = Self.cacheDirectory.appendingPathComponent("models--\(sanitized)")
        return FileManager.default.fileExists(atPath: modelDir.path)
    }

    /// Estimate total download size for models not yet cached.
    var pendingDownloadSizeGB: Double {
        models.filter { !$0.isDownloaded }.reduce(0) { $0 + $1.estimatedSizeGB }
    }

    /// Whether all models are cached and ready.
    var allModelsReady: Bool {
        models.allSatisfy { $0.isDownloaded }
    }
}
