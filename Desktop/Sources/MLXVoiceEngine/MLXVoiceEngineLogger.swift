//
//  MLXVoiceEngineLogger.swift
//  Fazm — Shared logger for MLX Voice Engine
//

import Foundation

/// Shared logging function for all MLXVoiceEngine files.
/// Using `internal` scope so it's visible across the module
/// without conflicting with other modules' `log` functions.
func mlxLog(_ message: String) {
    NSLog("[MLXVoiceEngine] %@", message)
}
