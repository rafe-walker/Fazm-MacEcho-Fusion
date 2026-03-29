#!/usr/bin/env bash
#
# setup-mlx-models.sh — Download MLX models for the Fazm + MacEcho Fusion voice engine
#

set -euo pipefail

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Fazm + MacEcho Fusion — MLX Model Setup                       ║"
echo "║  All models run locally on your M3 MacBook Pro via Apple MLX    ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Find huggingface-cli — check common install locations
HF_CLI=""
for candidate in \
    "$(python3 -m site --user-base 2>/dev/null)/bin/huggingface-cli" \
    "$HOME/Library/Python/3.9/bin/huggingface-cli" \
    "$HOME/Library/Python/3.10/bin/huggingface-cli" \
    "$HOME/Library/Python/3.11/bin/huggingface-cli" \
    "$HOME/Library/Python/3.12/bin/huggingface-cli" \
    "$HOME/Library/Python/3.13/bin/huggingface-cli" \
    "$(which huggingface-cli 2>/dev/null)" \
    ; do
    if [ -x "$candidate" ] 2>/dev/null; then
        HF_CLI="$candidate"
        break
    fi
done

if [ -z "$HF_CLI" ]; then
    echo "Installing huggingface-hub CLI..."
    pip3 install --user huggingface-hub 2>&1 | tail -3
    # Re-find after install
    HF_CLI="$(python3 -m site --user-base 2>/dev/null)/bin/huggingface-cli"
    if [ ! -x "$HF_CLI" ]; then
        echo "ERROR: Could not find huggingface-cli after install."
        echo "Try: export PATH=\"\$HOME/Library/Python/3.9/bin:\$PATH\" and re-run."
        exit 1
    fi
fi

echo "Using: $HF_CLI"
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
        "$HF_CLI" download "$repo_id" --quiet
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
