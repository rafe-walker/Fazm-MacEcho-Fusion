#!/bin/bash
# Promote a desktop release to the next channel
#
# Channel progression: staging → beta → stable
#
# Usage:
#   ./scripts/promote_release.sh v0.9.1+57-macos-staging
#
# Environment:
#   RELEASE_SECRET   - API shared secret (required)
#   FAZM_BACKEND_URL - Backend URL (default: https://fazm-backend-472661769323.us-east5.run.app)

set -e

# Load .env if available
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
elif [ -f "../.env" ]; then
    set -a
    source "../.env"
    set +a
fi

BACKEND_URL="${FAZM_BACKEND_URL:-https://fazm-backend-472661769323.us-east5.run.app}"
RELEASE_SECRET="${RELEASE_SECRET:-}"

TAG="${1:-}"

if [ -z "$TAG" ]; then
    echo "Usage: $0 <tag>"
    echo ""
    echo "Promotes a release to the next channel:"
    echo "  staging → beta → stable"
    echo ""
    echo "Example:"
    echo "  $0 v0.9.1+57-macos-staging"
    exit 1
fi

if [ -z "$RELEASE_SECRET" ]; then
    echo "Error: RELEASE_SECRET environment variable is required"
    exit 1
fi

echo "Promoting release: $TAG"
echo "  Backend: $BACKEND_URL"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X PATCH \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $RELEASE_SECRET" \
    -d "{\"tag\": \"$TAG\"}" \
    "$BACKEND_URL/api/releases/promote")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Release promoted successfully"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
else
    echo "✗ Failed to promote release (HTTP $HTTP_CODE)"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    exit 1
fi
