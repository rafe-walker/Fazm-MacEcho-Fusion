#!/bin/bash
# Move unreleased CHANGELOG.json entries into a versioned release.
#
# Usage:
#   ./scripts/prepare-release.sh 1.5.0
#
# This moves all items from "unreleased" into a new entry in "releases"
# with the given version and today's date, then clears "unreleased".

set -e

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo ""
    echo "Moves CHANGELOG.json 'unreleased' entries into a versioned release."
    echo ""
    echo "Example:"
    echo "  $0 1.5.0"
    exit 1
fi

CHANGELOG="CHANGELOG.json"

if [ ! -f "$CHANGELOG" ]; then
    echo "Error: $CHANGELOG not found"
    exit 1
fi

COUNT=$(python3 -c "
import json
with open('$CHANGELOG') as f:
    data = json.load(f)
print(len(data.get('unreleased', [])))
")

if [ "$COUNT" = "0" ]; then
    echo "No unreleased changes to move."
    exit 0
fi

DATE=$(date +%Y-%m-%d)

python3 -c "
import json

with open('$CHANGELOG', 'r') as f:
    data = json.load(f)

unreleased = data.get('unreleased', [])
release_entry = {
    'version': '$VERSION',
    'date': '$DATE',
    'changes': unreleased
}

releases = data.get('releases', [])
releases.insert(0, release_entry)

data['releases'] = releases
data['unreleased'] = []

with open('$CHANGELOG', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

echo "✓ Moved $COUNT changes to v$VERSION ($DATE)"
