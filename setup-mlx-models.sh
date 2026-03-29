#!/usr/bin/env bash
#
# setup-mlx-models.sh — Pre-download MLX models for Fazm + MacEcho Fusion
#
# Usage:
#   ./setup-mlx-models.sh                          # anonymous (slower)
#   HF_TOKEN=hf_xxx ./setup-mlx-models.sh          # authenticated (faster)
#   ./setup-mlx-models.sh --token hf_xxx           # same, via flag
#
# Get a free token at: https://huggingface.co/settings/tokens
#

set -euo pipefail

# Parse --token flag
HF_TOKEN="${HF_TOKEN:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --token) HF_TOKEN="$2"; shift 2 ;;
        --token=*) HF_TOKEN="${1#*=}"; shift ;;
        *) shift ;;
    esac
done

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Fazm + MacEcho Fusion — MLX Model Setup                       ║"
echo "║  All models run locally on your M3 MacBook Pro via Apple MLX    ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

if [ -n "$HF_TOKEN" ]; then
    echo "  🔑 Using HuggingFace token for authenticated downloads"
else
    echo "  ⚠️  No HF_TOKEN set — downloads will be slower."
    echo "     Get a free token: https://huggingface.co/settings/tokens"
    echo "     Then run: HF_TOKEN=hf_xxx ./setup-mlx-models.sh"
fi
echo ""

# Install huggingface_hub if missing
python3 -c "import huggingface_hub" 2>/dev/null || {
    echo "Installing huggingface-hub Python package..."
    pip3 install --user huggingface-hub
    echo ""
}

# Download models using pure Python
python3 - "$HF_TOKEN" << 'PYEOF'
import sys, os

token = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None

try:
    from huggingface_hub import snapshot_download, login
except ImportError:
    print("ERROR: huggingface_hub not importable.")
    print("Run: pip3 install --user huggingface-hub")
    sys.exit(1)

# Authenticate if token provided
if token:
    try:
        login(token=token, add_to_git_credential=False)
        print("  ✓ Authenticated with HuggingFace\n")
    except Exception as e:
        print(f"  ⚠️  Auth failed ({e}), continuing anonymously...\n")
        token = None

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
            snapshot_download(repo_id, token=token)
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
