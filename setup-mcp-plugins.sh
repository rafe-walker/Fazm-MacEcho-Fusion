#!/usr/bin/env bash
#
# setup-mcp-plugins.sh — Clone optional MCP server repos for Fazm
#
# These are optional plugins that run.sh builds and bundles into the app:
#   1. mcp-server-macos-use — GUI automation via Accessibility APIs
#   2. google_workspace_mcp — Gmail, Docs, Sheets, Calendar control
#   3. whatsapp-mcp-skill-macos — WhatsApp integration (private, skipped)
#

set -euo pipefail

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Fazm + MacEcho Fusion — MCP Plugin Setup                      ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# 1. mcp-server-macos-use (Swift — macOS GUI automation)
if [ -d "$HOME/mcp-server-macos-use" ]; then
    echo "  ✓ mcp-server-macos-use — already cloned"
    cd "$HOME/mcp-server-macos-use" && git pull --quiet 2>/dev/null && cd - >/dev/null
else
    echo "  ↓ Cloning mcp-server-macos-use (macOS GUI automation)..."
    git clone https://github.com/mediar-ai/mcp-server-macos-use.git "$HOME/mcp-server-macos-use"
    echo "  ✓ mcp-server-macos-use cloned"
fi
echo ""

# 2. google_workspace_mcp (Python — Gmail, Docs, Sheets, Calendar)
if [ -d "$HOME/google_workspace_mcp" ]; then
    echo "  ✓ google_workspace_mcp — already cloned"
    cd "$HOME/google_workspace_mcp" && git pull --quiet 2>/dev/null && cd - >/dev/null
else
    echo "  ↓ Cloning google_workspace_mcp (Gmail, Docs, Sheets, Calendar)..."
    git clone https://github.com/taylorwilsdon/google_workspace_mcp.git "$HOME/google_workspace_mcp"
    echo "  ✓ google_workspace_mcp cloned"
fi
echo ""

# 3. whatsapp-mcp-skill-macos (not publicly available)
if [ -d "$HOME/whatsapp-mcp-skill-macos" ]; then
    echo "  ✓ whatsapp-mcp-skill-macos — already present"
else
    echo "  ⚠️  whatsapp-mcp-skill-macos — not publicly available (Fazm private repo)"
    echo "     WhatsApp integration will be skipped during build."
fi
echo ""

# Check for uv (needed by google_workspace_mcp)
if ! command -v uv &>/dev/null; then
    echo "  ⚠️  'uv' not installed — needed for Google Workspace MCP Python deps"
    echo "     Install: brew install uv"
    echo "     Or: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

echo "════════════════════════════════════════════════════════════════════"
echo "  MCP plugins ready. Run: ./run.sh to build everything."
echo "════════════════════════════════════════════════════════════════════"
