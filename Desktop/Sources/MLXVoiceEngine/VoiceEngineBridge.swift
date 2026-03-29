//
//  VoiceEngineBridge.swift
//  Fazm — Bridge between MLX VoiceEngine and Fazm's existing systems
//
//  This file wires the new VoiceEngine into Fazm's PushToTalkManager,
//  FloatingControlBar, and ACP bridge. It provides:
//
//   1. Audio routing: AudioCaptureService → VoiceEngine (instead of DeepGram)
//   2. Transcription callback: VoiceEngine ASR → PushToTalkManager transcript
//   3. Full pipeline mode: VoiceEngine LLM → FloatingControlBar AI response
//   4. Fallback: If local pipeline isn't ready, fall through to ACP bridge
//
//  The integration preserves ALL of Fazm's existing functionality:
//   - Skills system (.claude/skills/ + skills-lock.json)
//   - OS control (Accessibility APIs, AppleScript, browser control)
//   - ACP bridge for Claude fallback
//   - Menubar, hotkeys, permissions
//

import Combine
import Foundation

/// Bridges the MLX VoiceEngine into Fazm's existing architecture.
@MainActor
final class VoiceEngineBridge: ObservableObject {

    static let shared = VoiceEngineBridge()

    // MARK: - State

    @Published var isLocalPipelineActive = false
    @Published var currentTranscript = ""
    @Published var currentResponse = ""
    @Published var isProcessing = false

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private init() {
        setupEventSubscription()
    }

    // MARK: - Setup

    /// Subscribe to VoiceEngine events and route them to Fazm's systems.
    private func setupEventSubscription() {
        let engine = VoiceEngine.shared

        engine.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)

        // Wire transcription callback
        engine.onTranscriptionReady = { [weak self] text in
            Task { @MainActor in
                self?.handleTranscription(text)
            }
        }

        // Wire LLM streaming
        engine.onLLMTextDelta = { [weak self] delta in
            Task { @MainActor in
                self?.currentResponse += delta
            }
        }

        // Wire response completion
        engine.onResponseComplete = { [weak self] fullText in
            Task { @MainActor in
                self?.handleResponseComplete(fullText)
            }
        }
    }

    // MARK: - Audio Routing

    /// Called by PushToTalkManager instead of sending audio to DeepGram.
    /// Routes audio data through the local VAD + ASR pipeline.
    func processAudioChunk(_ data: Data) {
        guard isLocalPipelineActive else { return }
        Task {
            await VoiceEngine.shared.processAudioData(data)
        }
    }

    /// Start the local pipeline for a PTT session.
    func startLocalSession() {
        guard VoiceEngine.shared.isModelLoaded else {
            log("[Bridge] Models not loaded, falling back to cloud")
            isLocalPipelineActive = false
            return
        }

        isLocalPipelineActive = true
        currentTranscript = ""
        currentResponse = ""
        isProcessing = false
        log("[Bridge] Local pipeline session started")
    }

    /// Stop the local pipeline session.
    func stopLocalSession() {
        VoiceEngine.shared.stop()
        isLocalPipelineActive = false
        isProcessing = false
        log("[Bridge] Local pipeline session stopped")
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: VoiceEngineEvent) {
        switch event {
        case .vadSpeechStart:
            isProcessing = true
            // Cancel any ongoing TTS (interruption)
            VoiceEngine.shared.cancelActivePipeline()

        case .vadSpeechEnd:
            break  // Processing continues in pipeline

        case .asrResult(let result):
            currentTranscript = result.text

        case .llmTokenDelta:
            break  // Handled by onLLMTextDelta callback

        case .llmComplete:
            isProcessing = false

        case .interrupted:
            currentResponse = ""
            isProcessing = false

        case .pipelineComplete:
            isProcessing = false

        case .engineReady:
            log("[Bridge] Engine ready")

        case .engineError(let msg):
            log("[Bridge] Engine error: \(msg)")
            isLocalPipelineActive = false

        default:
            break
        }
    }

    // MARK: - Fazm Integration

    /// Handle completed transcription — route to appropriate destination.
    private func handleTranscription(_ text: String) {
        currentTranscript = text

        switch VoiceEngine.shared.mode {
        case .transcriptionOnly:
            // Feed into Fazm's existing chat input (same as DeepGram path)
            FloatingControlBarManager.shared.openAIInputWithQuery(text)

        case .fullPipeline:
            // The engine handles LLM + TTS internally
            // But we also need to execute OS commands from the LLM response
            break
        }
    }

    /// Handle complete LLM response — check for actionable commands.
    private func handleResponseComplete(_ text: String) {
        currentResponse = text
        isProcessing = false

        // If the LLM response contains tool-use patterns, we can
        // optionally route them through Fazm's skill system.
        // For now, the response is displayed in the floating bar.
        //
        // Future: Parse structured tool calls from the LLM response
        // and execute them via ChatToolExecutor.
    }

    /// Check if the local pipeline should be used for the current session.
    /// Returns true if models are loaded and config says to use local pipeline.
    var shouldUseLocalPipeline: Bool {
        VoiceEngine.shared.isModelLoaded &&
        VoiceEngine.shared.config.pipeline.useLocalPipeline
    }
}

// MARK: - Logging

private func log(_ message: String) {
    NSLog("[MLXVoiceEngine] %@", message)
}
