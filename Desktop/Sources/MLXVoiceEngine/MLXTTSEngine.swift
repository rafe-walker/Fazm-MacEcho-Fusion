//
//  MLXTTSEngine.swift
//  Fazm — TTS via mlx-audio-swift
//
//  Uses Qwen3-TTS (the best available local TTS in mlx-audio-swift).
//  CosyVoice is not yet available in the Swift library, so we use
//  Qwen3-TTS which provides comparable quality with streaming support.
//

import AVFoundation
import Foundation
import MLX
import MLXAudioCore
import MLXAudioTTS

/// Text-to-Speech engine using MLX-native models.
/// Supports streaming audio generation for low-latency playback.
actor MLXTTSEngine {

    // MARK: - State

    private var model: (any SpeechGenerationModel)?
    private let config: MLXVoiceEngineConfig.TTSConfig
    private var isLoading = false
    private var isReady = false

    /// Audio player for streaming playback.
    private var audioPlayer: AVAudioPlayerNode?
    private var audioEngine: AVAudioEngine?

    // MARK: - Init

    init(config: MLXVoiceEngineConfig.TTSConfig = .init()) {
        self.config = config
    }

    // MARK: - Model Loading

    func loadModel() async throws {
        guard config.enabled else {
            log("[TTS] TTS disabled in config, skipping load")
            return
        }
        guard !isLoading && !isReady else { return }
        isLoading = true
        defer { isLoading = false }

        let startTime = CFAbsoluteTimeGetCurrent()
        log("[TTS] Loading TTS model: \(config.modelID)")

        let loadedModel = try await Qwen3TTSModel.fromPretrained(config.modelID)
        self.model = loadedModel
        isReady = true

        // Set up audio engine for playback
        setupAudioEngine()

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        log("[TTS] Model loaded in \(String(format: "%.2f", elapsed))s")
    }

    /// Warm up TTS with a short phrase.
    func warmUp() async {
        guard isReady, let model else { return }
        log("[TTS] Warming up TTS...")
        do {
            let _ = try await model.generate(
                text: "OK",
                voice: config.voice,
                refAudio: nil,
                refText: nil,
                language: "en",
                generationParameters: AudioGenerateParameters(maxTokens: 50)
            )
            log("[TTS] Warm-up complete")
        } catch {
            log("[TTS] Warm-up error (non-fatal): \(error)")
        }
    }

    // MARK: - Synthesis

    /// Synthesize text to audio and play it immediately.
    /// Returns when playback completes.
    func speak(_ text: String) async throws {
        guard let model, isReady, config.enabled else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        log("[TTS] Synthesizing: \"\(text.prefix(60))\"")

        let audio = try await model.generate(
            text: text,
            voice: config.voice,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: AudioGenerateParameters(
                maxTokens: config.maxTokens,
                temperature: config.temperature
            )
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let audioSamples = audio.asArray(Float.self)
        let audioDuration = Double(audioSamples.count) / Double(config.sampleRate)
        let rtf = elapsed / audioDuration
        log("[TTS] Synthesized \(String(format: "%.1f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.2f", rtf)))")

        // Play audio
        await playAudio(samples: audioSamples, sampleRate: model.sampleRate)
    }

    /// Stream TTS generation — yields audio chunks for real-time playback.
    func speakStreaming(_ text: String) async throws {
        guard let model, isReady, config.enabled else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        log("[TTS] Streaming synthesis: \"\(text.prefix(60))\"")

        var firstChunkTime: Double?

        let stream = model.generateStream(
            text: text,
            voice: config.voice,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: AudioGenerateParameters(
                maxTokens: config.maxTokens,
                temperature: config.temperature
            ),
            streamingInterval: 2.0
        )

        for try await event in stream {
            switch event {
            case .audio(let audioChunk):
                if firstChunkTime == nil {
                    firstChunkTime = CFAbsoluteTimeGetCurrent() - startTime
                    log("[TTS] First chunk in \(String(format: "%.3f", firstChunkTime!))s")
                }
                let samples = audioChunk.asArray(Float.self)
                await playAudioChunk(samples: samples, sampleRate: model.sampleRate)
            case .token:
                break  // Progress indicator, ignore
            case .info(let info):
                log("[TTS] Generation info: \(info.summary)")
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        log("[TTS] Streaming synthesis complete in \(String(format: "%.2f", elapsed))s")
    }

    /// Stop any ongoing playback (for interruption support).
    func stopPlayback() {
        audioPlayer?.stop()
    }

    // MARK: - Audio Playback

    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(config.sampleRate),
            channels: 1
        )!
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            self.audioEngine = engine
            self.audioPlayer = player
            log("[TTS] Audio engine started")
        } catch {
            log("[TTS] Failed to start audio engine: \(error)")
        }
    }

    private func playAudio(samples: [Float], sampleRate: Int) async {
        guard let player = audioPlayer, let engine = audioEngine else { return }

        let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: 1
        )!

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }

        if !engine.isRunning {
            try? engine.start()
        }

        player.play()
        player.scheduleBuffer(buffer)

        // Wait for playback to complete
        let duration = Double(samples.count) / Double(sampleRate)
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }

    private func playAudioChunk(samples: [Float], sampleRate: Int) async {
        guard let player = audioPlayer, let engine = audioEngine else { return }

        let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: 1
        )!

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }

        if !engine.isRunning {
            try? engine.start()
        }

        if !player.isPlaying {
            player.play()
        }
        player.scheduleBuffer(buffer)
    }
}

// MARK: - Logging Helper

private func log(_ message: String) {
    NSLog("[MLXVoiceEngine] %@", message)
}
