#!/bin/bash
#
# fazm-lock.sh — Simple file-based lock to prevent concurrent builds
#

LOCK_DIR="/tmp/fazm-build.lock"

fazm_acquire_lock() {
    local timeout="${1:-300}"
    local waited=0
    
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        if [ "$waited" -ge "$timeout" ]; then
            echo "ERROR: Could not acquire build lock after ${timeout}s. Another build may be running."
            echo "To force: rm -rf $LOCK_DIR"
            exit 1
        fi
        echo "Waiting for build lock (${waited}s / ${timeout}s)..."
        sleep 2
        waited=$((waited + 2))
    done
    
    # Store PID for staleness detection
    echo $$ > "$LOCK_DIR/pid"
    
    # Ensure cleanup on exit
    trap fazm_release_lock EXIT
}

fazm_release_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
}
