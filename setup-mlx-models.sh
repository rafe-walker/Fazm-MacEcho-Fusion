#!/usr/bin/env bash
#
# setup-mlx-models.sh — Download MLX models for the Fazm + MacEcho Fusion voice engine
#
# Models are cached in ~/.cache/huggingface/hub/ and reused across sessions.
# Total download: ~5.5 GB (first time only).
#
# Requirements:
#   - Python 3.10+ (for huggingface-cli)
#   - pip install huggingface-hub
#

set -euo pipefail

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Fazm + MacEcho Fusion — MLX Model Setup                       ║"
echo "║  All models run locally on your M3 MacBook Pro via Apple MLX    ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Check for huggingface-cli
if ! command -v huggingface-cli &>/dev/null; then
    echo "Installing huggingface-hub CLI..."
    pip3 install --break-system-packages huggingface-hub 2>/dev/null || pip3 install huggingface-hub
fi

CACHE_DIR="${HOME}/.cache/huggingface/hub"
mkdir -p "$CACHE_DIR"

download_model() {
    local repo_id="$1"
    local display_name="$2"
    local sanitized="${repo_id//\//-}"
    
    if [ -d "${CACHE_DIR}/models--${sanitized/\//-}" ] || [ -d "${CACHE_DIR}/models--${repo_id//\//-}" ]; then
        echo "  ✓ ${display_name} (${repo_id}) — already cached"
    else
        echo "  ↓ Downloading ${display_name} (${repo_id})..."
        huggingface-cli download "$repo_id" --quiet
        echo "  ✓ ${display_name} downloaded"
    fi
}

echo "Downloading models..."
echo ""

# 1. Silero VAD v5 (~1.2 MB) — downloaded automatically by speech-swift on first use
echo "  ✓ Silero VAD v5 (~1.2 MB) — auto-downloaded on first launch"

# 2. SenseVoice ASR (~500 MB)
download_model "mlx-community/SenseVoice-Small" "SenseVoice ASR"

# 3. Qwen 2.5 7B Instruct 4-bit (~4.5 GB)
download_model "mlx-community/Qwen2.5-7B-Instruct-4bit" "Qwen 2.5 7B LLM"

# 4. Qwen3-TTS (~400 MB)
download_model "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit" "Qwen3-TTS"

# 5. Fallback ASR (in case SenseVoice doesn't load)
download_model "mlx-community/Qwen3-ASR-1.7B-bf16" "Qwen3-ASR (fallback)"

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "  All models ready! Total cache: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)"
echo ""
echo "  Models cached in: $CACHE_DIR"
echo "  Run: ./run.sh to build and launch Fazm"
echo "════════════════════════════════════════════════════════════════════"
