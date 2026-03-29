#!/usr/bin/env bash
#
# setup-mlx-models.sh — Download MLX models for Fazm + MacEcho Fusion
#

set -euo pipefail

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Fazm + MacEcho Fusion — MLX Model Setup                       ║"
echo "║  All models run locally on your M3 MacBook Pro via Apple MLX    ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Ensure huggingface_hub is installed
python3 -c "import huggingface_hub" 2>/dev/null || {
    echo "Installing huggingface-hub..."
    pip3 install --user huggingface-hub 2>&1 | tail -3
}

# Use python3 -m to call it — avoids all PATH issues
HF="python3 -m huggingface_hub.commands.huggingface_cli"

# Verify it works
$HF version >/dev/null 2>&1 || {
    echo "ERROR: huggingface_hub installed but CLI not working."
    echo "Try: pip3 install --user --upgrade huggingface-hub"
    exit 1
}

echo "Using: $HF"
echo ""

CACHE_DIR="${HOME}/.cache/huggingface/hub"
mkdir -p "$CACHE_DIR"

download_model() {
    local repo_id="$1"
    local display_name="$2"
    local sanitized="${repo_id//\//--}"

    if [ -d "${CACHE_DIR}/models--${sanitized}" ]; then
        echo "  ✓ ${display_name} (${repo_id}) — already cached"
    else
        echo "  ↓ Downloading ${display_name} (${repo_id})..."
        $HF download "$repo_id" --quiet
        echo "  ✓ ${display_name} downloaded"
    fi
}

echo "Downloading models..."
echo ""

echo "  ✓ Silero VAD v5 (~1.2 MB) — auto-downloaded on first launch"

download_model "mlx-community/SenseVoice-Small" "SenseVoice ASR"
download_model "mlx-community/Qwen2.5-7B-Instruct-4bit" "Qwen 2.5 7B LLM"
download_model "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit" "Qwen3-TTS"
download_model "mlx-community/Qwen3-ASR-1.7B-bf16" "Qwen3-ASR (fallback)"

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "  All models ready! Total cache: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)"
echo "  Run: ./run.sh to build and launch Fazm"
echo "════════════════════════════════════════════════════════════════════"
