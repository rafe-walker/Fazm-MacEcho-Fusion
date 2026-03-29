//
//  SileroVAD.swift
//  Fazm — Silero VAD v5 via pure MLX (speech-swift)
//
//  Uses the speech-swift package which provides a native MLX implementation
//  of Silero VAD v5. Runs entirely on Apple Silicon Neural Engine with
//  ~40μs latency per 32ms frame — no ONNX dependency.
//
//  Ported from MacEcho's vad.py state machine, using speech-swift for
//  the underlying neural model instead of onnxruntime.
//

import Foundation
import SpeechVAD

// MARK: - VAD State

enum VADState: Sendable {
    case idle
    case speechStart
    case speechContinue
    case speechEnd
}

// MARK: - VAD Result

struct VADSegment: Sendable {
    let audio: [Float]
    let durationSeconds: Double
}

// MARK: - Silero VAD v5 Processor (Pure MLX)

/// Frame-by-frame speech detector matching MacEcho's VadProcessor.
/// Processes 32 ms frames (512 samples @ 16 kHz) and detects speech
/// boundaries using the Silero VAD v5 neural model via MLX.
///
/// State machine (identical to MacEcho):
///   IDLE → [speech prob > threshold] → SPEECH_START
///   SPEECH_START → SPEECH_CONTINUE (accumulating frames)
///   SPEECH_CONTINUE → [silence > silenceDuration] → SPEECH_END → returns segment
actor SileroVADProcessor {

    // MARK: - Configuration

    let config: MLXVoiceEngineConfig.VADConfig

    // MARK: - Neural Model

    private var vadModel: SileroVADModel?
    private var isReady = false

    // MARK: - Internal State

    /// Circular buffer for pre-speech padding.
    private var paddingBuffer: [[Float]] = []
    private let paddingFrames: Int

    /// Accumulated speech audio.
    private var speechBuffer: [Float] = []

    /// Current VAD state.
    private var state: VADState = .idle

    /// Consecutive silence frame count.
    private var silenceFrameCount: Int = 0
    private let silenceFrameThreshold: Int

    /// Consecutive speech frame count (for min duration gating).
    private var speechFrameCount: Int = 0
    private let minSpeechFrames: Int

    // MARK: - Init

    init(config: MLXVoiceEngineConfig.VADConfig = .init()) {
        self.config = config
        self.paddingFrames = max(1, Int(config.paddingDuration / config.frameDuration))
        self.silenceFrameThreshold = max(1, Int(config.silenceDuration / config.frameDuration))
        self.minSpeechFrames = max(1, Int(config.minSpeechDuration / config.frameDuration))
    }

    // MARK: - Model Loading

    /// Load the Silero VAD v5 model (pure MLX, ~1.2 MB, auto-downloaded from HuggingFace).
    func loadModel() async throws {
        guard !isReady else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        mlxLog("[VAD] Loading Silero VAD v5 (MLX)...")

        // speech-swift exports SileroVADModel (not SileroVAD)
        let model = try await SileroVADModel.fromPretrained()
        self.vadModel = model
        isReady = true

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        mlxLog("[VAD] Silero VAD loaded in \(String(format: "%.3f", elapsed))s")
    }

    // MARK: - Frame Processing

    /// Process a single 32 ms frame (512 samples @ 16 kHz).
    /// Returns a complete speech segment when speech ends, or nil.
    func processFrame(_ frame: [Float]) async -> (VADSegment?, VADState) {
        guard let model = vadModel, isReady else {
            return (nil, .idle)
        }

        // Run Silero VAD inference on this frame
        // speech-swift API: processChunk(_ samples: [Float]) -> Float (probability)
        let speechProb = model.processChunk(frame)
        let isSpeech = speechProb > config.threshold

        // Update padding ring buffer
        paddingBuffer.append(frame)
        if paddingBuffer.count > paddingFrames {
            paddingBuffer.removeFirst()
        }

        switch state {
        case .idle:
            if isSpeech {
                state = .speechStart
                speechFrameCount = 1
                silenceFrameCount = 0
                // Prepend padding for context
                speechBuffer = paddingBuffer.flatMap { $0 }
                speechBuffer.append(contentsOf: frame)
                return (nil, .speechStart)
            }
            return (nil, .idle)

        case .speechStart, .speechContinue:
            speechBuffer.append(contentsOf: frame)
            if isSpeech {
                speechFrameCount += 1
                silenceFrameCount = 0
                state = .speechContinue
                return (nil, .speechContinue)
            } else {
                silenceFrameCount += 1
                if silenceFrameCount >= silenceFrameThreshold {
                    state = .speechEnd
                    let segment = finalizeSpeechSegment()
                    reset()
                    if speechFrameCount >= minSpeechFrames {
                        return (segment, .speechEnd)
                    } else {
                        return (nil, .idle)
                    }
                }
                return (nil, .speechContinue)
            }

        case .speechEnd:
            reset()
            return (nil, .idle)
        }
    }

    /// Reset VAD state (e.g. after interruption).
    func reset() {
        state = .idle
        speechBuffer.removeAll()
        silenceFrameCount = 0
        speechFrameCount = 0
        // Reset the model's internal LSTM state
        vadModel?.resetState()
    }

    // MARK: - Private Helpers

    private func finalizeSpeechSegment() -> VADSegment {
        let duration = Double(speechBuffer.count) / Double(config.samplingRate)
        return VADSegment(audio: speechBuffer, durationSeconds: duration)
    }
}

