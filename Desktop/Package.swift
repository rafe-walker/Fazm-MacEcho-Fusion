// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Fazm",
    platforms: [
        .macOS("14.0")
    ],
    dependencies: [
        // --- Existing Fazm dependencies ---
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.0.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "8.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0"),
        .package(url: "https://github.com/m13v/macos-session-replay.git", from: "0.5.0"),
        .package(path: "LocalPackages/Highlightr"),
        .package(url: "https://github.com/m13v/ai-browser-profile-swift-light.git", from: "0.1.0"),

        // --- MLX Voice Engine dependencies ---
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.30.3"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.0"),
        // Pure-MLX Silero VAD v5 (no ONNX dependency, runs on Neural Engine)
        // Pure-MLX Silero VAD v5 — pinned to stable commit Mar 29 2026
        .package(url: "https://github.com/soniqo/speech-swift.git", revision: "3ef93ce3f630d684a179f29c7614d605e2ea509c"),
    ],
    targets: [
        .target(
            name: "ObjCExceptionCatcher",
            path: "ObjCExceptionCatcher",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Fazm",
            dependencies: [
                "ObjCExceptionCatcher",
                // Existing Fazm
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SessionReplay", package: "macos-session-replay"),
                .product(name: "Highlightr", package: "Highlightr"),
                .product(name: "BrowserProfileLight", package: "ai-browser-profile-swift-light"),
                // MLX Voice Engine
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                // Silero VAD v5 (pure MLX, ~40μs/frame on M-series)
                .product(name: "SpeechVAD", package: "speech-swift"),
            ],
            path: "Sources",
            resources: [
                .copy("BundledSkills"),
                .process("Resources"),
            ]
        )
    ]
)
