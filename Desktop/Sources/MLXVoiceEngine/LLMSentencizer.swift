//
//  LLMSentencizer.swift
//  Fazm — Real-time sentence boundary detection
//
//  Ported from MacEcho's sentencizer.py.
//  Splits streaming LLM output into complete sentences for TTS,
//  enabling low-latency speech: each sentence is sent to TTS immediately.
//

import Foundation

/// Accumulates streaming LLM tokens and emits complete sentences.
/// Matches MacEcho's LLMSentencizer behavior exactly.
struct LLMSentencizer: Sendable {
    /// Buffer of accumulated text not yet emitted.
    private var buffer: String = ""
    /// Whether to treat newlines as sentence separators.
    let newlineAsSeparator: Bool
    /// Whether to strip newlines from emitted sentences.
    let stripNewlines: Bool

    /// Sentence-ending punctuation characters.
    private static let sentenceEnders: CharacterSet = CharacterSet(charactersIn: ".!?。！？；;")
    /// Minimum sentence length before we'll split.
    private static let minSentenceLength = 10

    init(newlineAsSeparator: Bool = true, stripNewlines: Bool = true) {
        self.newlineAsSeparator = newlineAsSeparator
        self.stripNewlines = stripNewlines
    }

    /// Process an incoming token/chunk from the LLM.
    /// Returns any complete sentences detected (may be empty or multiple).
    mutating func processChunk(_ chunk: String) -> [String] {
        buffer += chunk
        return extractSentences()
    }

    /// Flush any remaining text in the buffer (call when LLM generation ends).
    mutating func finish() -> [String] {
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        if remaining.isEmpty { return [] }
        return [remaining]
    }

    // MARK: - Private

    private mutating func extractSentences() -> [String] {
        var sentences: [String] = []

        while true {
            guard let (sentence, rest) = findSentenceBoundary(in: buffer) else { break }
            let trimmed = stripNewlines
                ? sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                : sentence.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                sentences.append(trimmed)
            }
            buffer = rest
        }

        return sentences
    }

    /// Find the first sentence boundary in the text.
    /// Returns (sentence, remainingText) or nil if no boundary found.
    private func findSentenceBoundary(in text: String) -> (String, String)? {
        // Check for newline separator first
        if newlineAsSeparator {
            if let nlRange = text.rangeOfCharacter(from: .newlines) {
                let sentence = String(text[text.startIndex..<nlRange.lowerBound])
                let rest = String(text[nlRange.upperBound...])
                if sentence.count >= Self.minSentenceLength || !rest.isEmpty {
                    return (sentence, rest)
                }
            }
        }

        // Check for sentence-ending punctuation
        for (index, char) in text.enumerated() {
            if Self.sentenceEnders.contains(char.unicodeScalars.first!) {
                let splitIndex = text.index(text.startIndex, offsetBy: index + 1)
                let sentence = String(text[text.startIndex..<splitIndex])
                let rest = String(text[splitIndex...])

                // Only split if we have enough content
                if sentence.count >= Self.minSentenceLength {
                    return (sentence, rest)
                }
            }
        }

        return nil
    }
}
