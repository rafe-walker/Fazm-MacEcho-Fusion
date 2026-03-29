//
//  MLXLLMEngine.swift
//  Fazm — Qwen LLM via mlx-swift-lm
//
//  Ported from MacEcho's mlx_qwen.py.
//  Loads quantized Qwen model and provides streaming generation.
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Local LLM engine using Qwen on MLX.
/// Supports streaming token generation and conversation context management.
actor MLXLLMEngine {

    // MARK: - State

    private var modelContainer: ModelContainer?
    private let config: MLXVoiceEngineConfig.LLMConfig
    private var isLoading = false
    private var isReady = false

    /// Conversation history for context (mirrors MacEcho's ConversationContextManager).
    private var conversationHistory: [ConversationTurn] = []

    // MARK: - Init

    init(config: MLXVoiceEngineConfig.LLMConfig = .init()) {
        self.config = config
    }

    // MARK: - Model Loading

    /// Load the Qwen model from HuggingFace Hub.
    func loadModel() async throws {
        guard !isLoading && !isReady else { return }
        isLoading = true
        defer { isLoading = false }

        let startTime = CFAbsoluteTimeGetCurrent()
        mlxLog("[LLM] Loading model: \(config.modelID)")

        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(id: config.modelID)
        )
        self.modelContainer = container
        isReady = true

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        mlxLog("[LLM] Model loaded in \(String(format: "%.2f", elapsed))s")
    }

    /// Warm up with a short generation to prime Metal.
    func warmUp() async {
        guard isReady else { return }
        mlxLog("[LLM] Warming up Qwen...")
        // Generate a short response to prime caches
        var discarded = ""
        for await token in generateStream(prompt: "Hi", skipContext: true) {
            discarded += token
            if discarded.count > 5 { break }
        }
        mlxLog("[LLM] Warm-up complete")
    }

    // MARK: - Generation

    /// Generate a streaming response for the given user prompt.
    /// Yields individual tokens as they are generated.
    func generateStream(prompt: String, skipContext: Bool = false) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let container = self.modelContainer, self.isReady else {
                    mlxLog("[LLM] Model not ready")
                    continuation.finish()
                    return
                }

                // Build messages array with context
                var messages: [[String: String]] = [
                    ["role": "system", "content": self.config.systemPrompt]
                ]

                if !skipContext {
                    // Add conversation history
                    for turn in self.conversationHistory.suffix(self.config.maxContextRounds) {
                        messages.append(["role": "user", "content": turn.userMessage])
                        messages.append(["role": "assistant", "content": turn.assistantMessage])
                    }
                }

                messages.append(["role": "user", "content": prompt])

                let startTime = CFAbsoluteTimeGetCurrent()
                var fullResponse = ""
                var tokenCount = 0

                do {
                    let result = try await container.perform { (model, tokenizer) in
                        // Apply chat template
                        let chatPrompt = tokenizer.applyChatTemplate(
                            messages: messages
                        )
                        let promptTokens = tokenizer.encode(text: chatPrompt)

                        // Stream generate
                        return try MLXLMCommon.generate(
                            input: .init(tokens: MLXArray(promptTokens)),
                            parameters: .init(
                                temperature: self.config.temperature,
                                topP: self.config.topP
                            ),
                            model: model,
                            tokenizer: tokenizer,
                            extraEOSTokens: nil
                        ) { tokens in
                            // This callback is called per token
                            if let text = tokenizer.decode(tokens: [tokens.tokens.last!.item(Int.self)]) {
                                continuation.yield(text)
                                fullResponse += text
                                tokenCount += 1
                            }
                            // Continue generating up to maxTokens
                            return tokenCount < self.config.maxTokens ? .more : .stop
                        }
                    }

                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    let tps = Double(tokenCount) / elapsed
                    mlxLog("[LLM] Generated \(tokenCount) tokens in \(String(format: "%.2f", elapsed))s (\(String(format: "%.1f", tps)) tok/s)")

                    // Save to context
                    if !skipContext && !fullResponse.isEmpty {
                        await self.addToContext(user: prompt, assistant: fullResponse)
                    }
                } catch {
                    mlxLog("[LLM] Generation error: \(error)")
                }

                continuation.finish()
            }
        }
    }

    /// Non-streaming generation for simple queries.
    func generate(prompt: String) async throws -> String {
        var result = ""
        for await token in generateStream(prompt: prompt) {
            result += token
        }
        return result
    }

    // MARK: - Context Management

    /// Add a completed exchange to conversation history.
    private func addToContext(user: String, assistant: String) {
        conversationHistory.append(ConversationTurn(
            userMessage: user,
            assistantMessage: assistant
        ))
        pruneContextIfNeeded()
    }

    /// Remove oldest turns when exceeding token budget.
    private func pruneContextIfNeeded() {
        while estimateTokenCount() > config.contextWindowSize && !conversationHistory.isEmpty {
            conversationHistory.removeFirst()
        }
    }

    /// Rough token estimation (same heuristic as MacEcho: len/2).
    private func estimateTokenCount() -> Int {
        conversationHistory.reduce(0) { total, turn in
            total + (turn.userMessage.count + turn.assistantMessage.count) / 2
        }
    }

    /// Clear all conversation context.
    func clearContext() {
        conversationHistory.removeAll()
    }
}

// MARK: - Conversation Turn

struct ConversationTurn: Sendable {
    let userMessage: String
    let assistantMessage: String
}

