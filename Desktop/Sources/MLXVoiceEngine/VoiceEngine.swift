//
//  VoiceEngine.swift
//  Fazm — MLX-Native Voice Engine (MacEcho Pipeline)
//
//  This is the central orchestrator that replaces Fazm's cloud-based
//  STT (DeepGram) with a fully local, MLX-accelerated pipeline:
//
//    Microphone → Silero VAD v5 (32ms frames, ~40μs/frame)
//                  → SenseVoice ASR (or Qwen3-ASR fallback)
//                     → Qwen2.5-7B LLM (streaming tokens)
//                        → Qwen3-TTS (streaming audio)
//
//  All models run on Apple Silicon via MLX. No cloud calls.
//  Designed to plug into Fazm's existing PushToTalkManager and
//  FloatingControlBar for seamless integration.
//

import Combine
import Foundation

// MARK: - Pipeline Events (Message Bus)

/// Event-driven message bus matching MacEcho's architecture.
/// Each pipeline stage emits events that downstream stages consume.
enum VoiceEngineEvent: Sendable {
    // Pipeline lifecycle
    case engineReady
    case engineError(String)

    // VAD events
    case vadSpeechStart
    case vadSpeechEnd(segment: VADSegment)

    // ASR events
    case asrResult(ASRResult)

    // LLM events
    case llmTokenDelta(String)
    case llmComplete(fullText: String)

    // TTS events
    case ttsSpeaking(sentence: String)
    case ttsDone

    // Control
    case interrupted
    case pipelineComplete
}

// MARK: - Voice Engine

/// The main orchestrator for the fully-local MLX voice pipeline.
/// Manages the complete flow: audio → VAD → ASR → LLM → TTS.
///
/// Usage:
///   1. Call `initialize()` on app launch to load models.
///   2. Feed audio frames via `processAudioFrame(_:)` (32ms chunks from AudioCaptureService).
///   3. Subscribe to `eventPublisher` for pipeline events.
///   4. The engine automatically chains: VAD → ASR → LLM → TTS.
///
/// For Fazm integration, the engine can operate in two modes:
///   - **Full pipeline** (default): Runs the complete chain and speaks the response.
///   - **Transcription only**: Just VAD + ASR, feeds text into Fazm's existing ACP bridge.
@MainActor
final class VoiceEngine: ObservableObject {

    // MARK: - Singleton

    static let shared = VoiceEngine()

    // MARK: - Configuration

    @Published var config: MLXVoiceEngineConfig

    // MARK: - Sub-engines

    private let vad: SileroVADProcessor
    private let asr: MLXASREngine
    private let llm: MLXLLMEngine
    private let tts: MLXTTSEngine

    // MARK: - Event Bus

    /// Publisher for pipeline events. UI and Fazm components subscribe here.
    let eventPublisher = PassthroughSubject<VoiceEngineEvent, Never>()

    // MARK: - State

    enum EngineState {
        case uninitialized
        case loading
        case ready
        case listening       // VAD active, waiting for speech
        case processing      // Speech detected, running ASR → LLM → TTS
        case speaking        // TTS playing response
        case error(String)
    }

    @Published private(set) var state: EngineState = .uninitialized
    @Published private(set) var isModelLoaded = false

    /// Whether to run the full pipeline (LLM + TTS) or just transcription.
    @Published var mode: PipelineMode = .fullPipeline

    enum PipelineMode {
        case fullPipeline       // VAD → ASR → LLM → TTS (fully local)
        case transcriptionOnly  // VAD → ASR → feeds into Fazm's ACP bridge
    }

    /// Current audio frame buffer for 32ms processing.
    private var audioBuffer: [Float] = []
    private let frameSize: Int

    /// Active pipeline task (for cancellation on interruption).
    private var activePipelineTask: Task<Void, Never>?

    /// Sentencizer for streaming LLM → TTS.
    private var sentencizer = LLMSentencizer()

    /// Callback: called when transcription is ready (for Fazm integration).
    var onTranscriptionReady: ((String) -> Void)?

    /// Callback: called with streaming LLM text deltas (for UI updates).
    var onLLMTextDelta: ((String) -> Void)?

    /// Callback: called when full response is ready.
    var onResponseComplete: ((String) -> Void)?

    // MARK: - Init

    private init() {
        let config = MLXVoiceEngineConfig.load()
        self.config = config
        self.frameSize = config.vad.frameSize  // 512 samples @ 16 kHz = 32 ms

        self.vad = SileroVADProcessor(config: config.vad)
        self.asr = MLXASREngine(config: config.asr)
        self.llm = MLXLLMEngine(config: config.llm)
        self.tts = MLXTTSEngine(config: config.tts)
    }

    // MARK: - Initialization

    /// Load all models. Call on app launch (or lazily on first use).
    /// Models are cached in ~/.cache/huggingface/ after first download.
    func initialize() async {
        guard case .uninitialized = state else {
            // Also allow re-initialization from error state
            if case .error = state { } else { return }
        }
        state = .loading
        mlxLog("[Engine] Initializing MLX Voice Engine...")

        do {
            // Load models in parallel where possible
            async let vadLoad: () = vad.loadModel()
            async let asrLoad: () = asr.loadModel()
            async let llmLoad: () = llm.loadModel()
            async let ttsLoad: () = tts.loadModel()

            try await vadLoad
            try await asrLoad
            try await llmLoad
            try await ttsLoad

            // Warm up models for faster first inference
            if config.pipeline.warmUpOnLaunch {
                mlxLog("[Engine] Warming up models...")
                await vad.reset()  // No warm-up needed, ~40μs per frame
                await asr.warmUp()
                await llm.warmUp()
                await tts.warmUp()
            }

            state = .ready
            isModelLoaded = true
            eventPublisher.send(.engineReady)
            mlxLog("[Engine] All models loaded and ready")

            // Log which ASR model was loaded
            let asrModel = await asr.currentModel
            mlxLog("[Engine] ASR model: \(asrModel?.rawValue ?? "none")")

        } catch {
            let msg = "Model loading failed: \(error.localizedDescription)"
            state = .error(msg)
            eventPublisher.send(.engineError(msg))
            mlxLog("[Engine] ERROR: \(msg)")
        }
    }

    // MARK: - Audio Processing

    /// Feed raw audio samples from AudioCaptureService.
    /// Expects Float32 PCM at 16 kHz. Internally buffers and processes
    /// 32 ms frames through the VAD.
    func processAudioSamples(_ samples: [Float]) async {
        switch state {
        case .ready, .listening, .processing: break
        default: return
        }

        if case .ready = state {
            state = .listening
        }

        // Buffer incoming samples
        audioBuffer.append(contentsOf: samples)

        // Process complete 32 ms frames
        while audioBuffer.count >= frameSize {
            let frame = Array(audioBuffer.prefix(frameSize))
            audioBuffer.removeFirst(frameSize)

            let (segment, vadState) = await vad.processFrame(frame)

            switch vadState {
            case .speechStart:
                eventPublisher.send(.vadSpeechStart)
                // Cancel any ongoing pipeline (interruption support)
                cancelActivePipeline()

            case .speechEnd:
                if let segment = segment {
                    eventPublisher.send(.vadSpeechEnd(segment: segment))
                    // Kick off the rest of the pipeline
                    startPipeline(for: segment)
                }

            case .speechContinue, .idle:
                break
            }
        }
    }

    /// Convenience: process raw Int16 PCM data (from Fazm's AudioCaptureService).
    func processAudioData(_ data: Data) async {
        let int16Samples = data.withUnsafeBytes {
            Array($0.bindMemory(to: Int16.self))
        }
        // Convert Int16 → Float32 (normalized to -1.0 ... 1.0)
        let floatSamples = int16Samples.map { Float($0) / Float(Int16.max) }
        await processAudioSamples(floatSamples)
    }

    // MARK: - Pipeline Orchestration

    /// Start the ASR → LLM → TTS pipeline for a completed speech segment.
    private func startPipeline(for segment: VADSegment) {
        activePipelineTask = Task { [weak self] in
            guard let self else { return }
            await self.runPipeline(segment: segment)
        }
    }

    /// The core pipeline: ASR → (optional LLM → TTS).
    private func runPipeline(segment: VADSegment) async {
        state = .processing

        // 1. ASR: Transcribe the speech segment
        guard let asrResult = try? await asr.transcribe(audioSamples: segment.audio) else {
            mlxLog("[Engine] ASR returned nil")
            state = .listening
            return
        }

        let transcribedText = asrResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcribedText.isEmpty else {
            mlxLog("[Engine] Empty transcription, ignoring")
            state = .listening
            return
        }

        eventPublisher.send(.asrResult(asrResult))
        onTranscriptionReady?(transcribedText)

        // If transcription-only mode, stop here (text goes to ACP bridge)
        guard mode == .fullPipeline else {
            state = .listening
            eventPublisher.send(.pipelineComplete)
            return
        }

        // 2. LLM: Generate response with streaming
        var fullResponse = ""
        sentencizer = LLMSentencizer()

        for await token in await llm.generateStream(prompt: transcribedText) {
            // Check for cancellation (interruption)
            if Task.isCancelled { break }

            fullResponse += token
            eventPublisher.send(.llmTokenDelta(token))
            onLLMTextDelta?(token)

            // 3. Sentencize for TTS
            let sentences = sentencizer.processChunk(token)
            for sentence in sentences {
                if Task.isCancelled { break }
                await speakSentence(sentence)
            }
        }

        // Flush remaining text to TTS
        if !Task.isCancelled {
            let remaining = sentencizer.finish()
            for sentence in remaining {
                if Task.isCancelled { break }
                await speakSentence(sentence)
            }
        }

        if !Task.isCancelled {
            eventPublisher.send(.llmComplete(fullText: fullResponse))
            onResponseComplete?(fullResponse)
            eventPublisher.send(.pipelineComplete)
        }

        state = .listening
    }

    /// Speak a single sentence via TTS.
    private func speakSentence(_ sentence: String) async {
        guard config.pipeline.enableTTS else { return }
        state = .speaking
        eventPublisher.send(.ttsSpeaking(sentence: sentence))

        do {
            if config.pipeline.enableStreaming {
                try await tts.speakStreaming(sentence)
            } else {
                try await tts.speak(sentence)
            }
        } catch {
            mlxLog("[Engine] TTS error: \(error)")
        }

        eventPublisher.send(.ttsDone)
    }

    // MARK: - Interruption

    /// Cancel the active pipeline (called when new speech detected mid-response).
    func cancelActivePipeline() {
        activePipelineTask?.cancel()
        activePipelineTask = nil
        Task {
            await tts.stopPlayback()
            await vad.reset()
        }
        sentencizer = LLMSentencizer()
        eventPublisher.send(.interrupted)
        mlxLog("[Engine] Pipeline interrupted")
    }

    /// Stop all processing and reset state.
    func stop() {
        cancelActivePipeline()
        audioBuffer.removeAll()
        state = .ready
    }

    // MARK: - Context Management

    /// Clear LLM conversation history.
    func clearContext() async {
        await llm.clearContext()
    }
}

