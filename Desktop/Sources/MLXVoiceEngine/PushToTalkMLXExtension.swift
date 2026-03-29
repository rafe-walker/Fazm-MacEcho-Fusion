//
//  PushToTalkMLXExtension.swift
//  Fazm — MLX VoiceEngine integration with PushToTalkManager
//
//  This extension adds local MLX pipeline support to PushToTalkManager.
//  When the VoiceEngine is loaded and configured for local pipeline,
//  audio is routed through VAD → ASR locally instead of DeepGram.
//
//  Integration approach:
//   - We modify startMicCapture's audio callback to ALSO feed the
//     local VoiceEngine when it's active.
//   - In transcription-only mode, the VoiceEngine's ASR result replaces
//     DeepGram's transcript.
//   - In full-pipeline mode, the VoiceEngine handles everything
//     (LLM + TTS), bypassing the ACP bridge entirely.
//
//  This file does NOT modify PushToTalkManager.swift directly.
//  Instead, Fazm's startAudioTranscription() is extended to check
//  VoiceEngineBridge.shouldUseLocalPipeline first.
//

import Foundation

// MARK: - PushToTalkManager Integration Notes
//
// The integration requires minimal changes to PushToTalkManager.swift:
//
// 1. In startAudioTranscription(), add at the top:
//
//    if VoiceEngineBridge.shared.shouldUseLocalPipeline {
//        VoiceEngineBridge.shared.startLocalSession()
//        startMicCapture(localMLX: true)
//        return
//    }
//
// 2. In startMicCapture(), add a localMLX path:
//
//    if localMLX {
//        VoiceEngineBridge.shared.processAudioChunk(audioData)
//    }
//
// 3. In stopAudioTranscription(), add:
//
//    VoiceEngineBridge.shared.stopLocalSession()
//
// These changes are marked with "// [MLX-FUSION]" comments in the
// modified PushToTalkManager.swift file.

// MARK: - FazmApp Integration Notes
//
// In FazmApp.swift, add VoiceEngine initialization:
//
//    .task {
//        await VoiceEngine.shared.initialize()
//    }
//
// This loads all MLX models at app launch (cached after first download).
