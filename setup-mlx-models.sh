#!/usr/bin/env bash
#
# setup-mlx-models.sh — Pre-download MLX models for Fazm + MacEcho Fusion
#
# NOTE: This script is OPTIONAL. The Swift app auto-downloads models on
# first launch via mlx-audio-swift / mlx-swift-lm. This just pre-caches
# them so the first launch is faster.
#

set -euo pipefail

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Fazm + MacEcho Fusion — MLX Model Setup                       ║"
echo "║  All models run locally on your M3 MacBook Pro via Apple MLX    ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Install huggingface_hub if missing
python3 -c "import huggingface_hub" 2>/dev/null || {
    echo "Installing huggingface-hub Python package..."
    pip3 install --user huggingface-hub
    echo ""
}

# Download models using pure Python — no CLI binary needed
python3 << 'PYEOF'
import sys
try:
    from huggingface_hub import snapshot_download
except ImportError:
    print("ERROR: huggingface_hub not importable.")
    print("Run: pip3 install --user huggingface-hub")
    sys.exit(1)

import os

models = [
    ("mlx-community/SenseVoice-Small",                  "SenseVoice ASR",         "~500 MB"),
    ("mlx-community/Qwen2.5-7B-Instruct-4bit",          "Qwen 2.5 7B LLM",       "~4.5 GB"),
    ("mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",     "Qwen3-TTS",             "~400 MB"),
    ("mlx-community/Qwen3-ASR-1.7B-bf16",               "Qwen3-ASR (fallback)",  "~1.7 GB"),
]

cache_dir = os.path.expanduser("~/.cache/huggingface/hub")

print("  ✓ Silero VAD v5 (~1.2 MB) — auto-downloaded on first launch")
print()

for repo_id, name, size in models:
    sanitized = repo_id.replace("/", "--")
    cached_path = os.path.join(cache_dir, f"models--{sanitized}")
    if os.path.isdir(cached_path):
        print(f"  ✓ {name} ({repo_id}) — already cached")
    else:
        print(f"  ↓ Downloading {name} ({repo_id}, {size})...")
        try:
            snapshot_download(repo_id)
            print(f"  ✓ {name} downloaded")
        except Exception as e:
            print(f"  ✗ {name} failed: {e}")
            print(f"    (Will auto-download on first app launch instead)")

print()
PYEOF

CACHE_DIR="${HOME}/.cache/huggingface/hub"
echo "════════════════════════════════════════════════════════════════════"
echo "  Models cached in: $CACHE_DIR"
if [ -d "$CACHE_DIR" ]; then
    echo "  Total cache size: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)"
fi
echo ""
echo "  Run: ./run.sh to build and launch Fazm"
echo "════════════════════════════════════════════════════════════════════"
