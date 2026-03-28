# test-release: Smoke Test a Fazm Release

Smoke test a Fazm release on **both** the local production app and the MacStadium remote machine. Use after promoting a release to beta or stable, or when the user says "test the release", "smoke test", "verify the build works".

**This skill does NOT build anything.** It tests the shipped product that users receive via Sparkle auto-update.

## Prerequisites

- The release must already be promoted (registered in Firestore on beta or stable channel)
- The production Fazm app must be installed locally (`/Applications/Fazm.app`)
- MacStadium remote machine must be reachable (`./scripts/macstadium/ssh.sh`)

## Flow

### Step 1: Trigger Update on Local Machine

1. Open the production Fazm app: `open -a "Fazm"`
2. Use `macos-use` MCP to click the "Update Available" button in the sidebar (or Settings > About > "Check for Updates")
3. Sparkle shows the update dialog — verify it shows the correct version and release notes
4. **Do NOT check "Automatically download and install updates"** — we want to manually verify each step
5. Click "Install Update" and wait for the app to restart
6. After restart, verify the new version in the title bar or About screen

### Step 2: Send Test Queries on Local Machine

Send each query via distributed notification. Wait 15 seconds between queries for the AI to respond. After each query, check `/private/tmp/fazm.log` for errors.

```bash
# Query 1: Basic chat (AI responds at all)
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.fazm.testQuery"), object: nil, userInfo: ["text": "What is 2+2?"], deliverImmediately: true); RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))'

# Query 2: Memory recall (memory pipeline works)
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.fazm.testQuery"), object: nil, userInfo: ["text": "What do you remember about me?"], deliverImmediately: true); RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))'

# Query 3: Tool use / Google Workspace (MCP tools connected)
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.fazm.testQuery"), object: nil, userInfo: ["text": "What events do I have on my calendar today?"], deliverImmediately: true); RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))'

# Query 4: File system tool use
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.fazm.testQuery"), object: nil, userInfo: ["text": "List the files on my Desktop"], deliverImmediately: true); RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))'
```

After each query:
- Check logs for errors: `grep -i "error\|fail\|crash\|unauthorized\|401" /private/tmp/fazm.log | tail -5`
- Check the AI actually responded: `grep -i "AGENT_BRIDGE\|response\|completed" /private/tmp/fazm.log | tail -10`

### Step 3: Update and Test on MacStadium Remote Machine

1. Check Fazm is running: `./scripts/macstadium/ssh.sh "pgrep -la Fazm"` (launch if needed)
2. Use `macos-use-remote` MCP to click "Update Available" or navigate to Settings > About > "Check for Updates"
3. Verify update dialog shows correct version, click "Install Update" (do NOT auto-update)
4. After restart, verify version, then send the same 4 test queries via SSH:
   ```bash
   ./scripts/macstadium/ssh.sh "xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"com.fazm.testQuery\"), object: nil, userInfo: [\"text\": \"YOUR_QUERY\"], deliverImmediately: true); RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))'"
   ```
5. Check remote logs: `./scripts/macstadium/ssh.sh "grep -iE 'error|fail|crash|completed' /tmp/fazm.log | tail -10"`

### Step 5: Check Sentry

After all queries are sent, check Sentry for new errors in this release version:
```bash
./scripts/sentry-release.sh
```

### Step 6: Report Results

Report a summary table:

| Test | Local | Remote |
|------|-------|--------|
| App updated to vX.Y.Z | pass/fail | pass/fail |
| Basic chat ("2+2") | pass/fail | pass/fail |
| Memory recall | pass/fail | pass/fail |
| Tool use (calendar) | pass/fail | pass/fail |
| File system (Desktop) | pass/fail | pass/fail |
| Sentry errors | 0 new / N new | — |

**pass** = AI responded without errors in logs
**fail** = no response, error in logs, or crash

## What Counts as a Failure

- **Sparkle update fails** — this is a hard failure. Do NOT work around it with manual ZIP install. If Sparkle can't update, the test fails. Common cause: broken code signature from `__pycache__` files written inside the app bundle.
- App doesn't update (Sparkle error, appcast not serving correct version)
- Query gets no AI response within 60 seconds
- Logs show `error`, `crash`, `unauthorized`, `401`, or `failed` during the query
- App crashes or becomes unresponsive
- Sentry shows new issues for this release version
