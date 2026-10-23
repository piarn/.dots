#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

AP=$REPO/agent-pool/.agent-pool
export AGENT_POOL_DIR=$TMP/pool
unset CLAUDECODE AGENT_POOL_ACCOUNT AGENT_POOL_WRAPPER CLAUDE_CONFIG_DIR
pool() { "$AP/bin/agent-pool" "$@"; }

# setup: two accounts, shared state linked into both, the hook registered
mkdir -p "$AGENT_POOL_DIR/claude1/projects/p" && echo t >"$AGENT_POOL_DIR/claude1/projects/p/s1.jsonl"
echo '{"theme": "dark"}' >"$AGENT_POOL_DIR/claude1/settings.json"
pool setup >/dev/null
check "setup: claude2 created" [ -d "$AGENT_POOL_DIR/claude2" ]
check "setup: claude1's sessions moved to shared" [ -f "$AGENT_POOL_DIR/shared/projects/p/s1.jsonl" ]
check "setup: claude2 sees them" [ -f "$AGENT_POOL_DIR/claude2/projects/p/s1.jsonl" ]
check "setup: settings kept" grep -q '"theme": "dark"' "$AGENT_POOL_DIR/shared/settings.json"
check "setup: rate-limit hook registered" grep -q 'on-limit' "$AGENT_POOL_DIR/shared/settings.json"
pool setup >/dev/null
check "setup again: hook registered once" [ "$(grep -c 'on-limit' "$AGENT_POOL_DIR/shared/settings.json")" = 1 ]

# pick: logged-in accounts only, the active one first, limited ones skipped
check "nobody logged in: no pick" not pool pick
echo '{}' >"$AGENT_POOL_DIR/claude1/.credentials.json"
echo '{}' >"$AGENT_POOL_DIR/claude2/.credentials.json"
check "both usable: active (claude1)" [ "$(pool pick)" = claude1 ]
echo "$(( $(date +%s) + 600 ))" >"$AGENT_POOL_DIR/state/claude1.limited"
check "claude1 limited: claude2" [ "$(pool pick)" = claude2 ]
echo "{\"at\": 0, \"rate_limits\": {\"five_hour\": {\"used_percentage\": 100, \"resets_at\": $(( $(date +%s) + 300 ))}}}" \
    >"$AGENT_POOL_DIR/state/claude2.usage.json"
check "both full: no rollover target" not pool pick --except claude1
check "both full: the one resetting first" [ "$(pool pick 2>/dev/null)" = claude2 ]
pool clear
check "clear: claude1 again" [ "$(pool pick)" = claude1 ]

# hook: a limit message's reset time is recorded
echo '{"session_id":"s1","error":"rate_limit","last_assistant_message":"Claude AI usage limit reached|4102444800"}' \
    | AGENT_POOL_ACCOUNT=claude1 "$AP/lib/on-limit"
check "hook: limit until the epoch in the message" [ "$(cut -d' ' -f1 "$AGENT_POOL_DIR/state/claude1.limited")" = 4102444800 ]
pool clear

# rollover: the fake claude hits the limit on claude1, the wrapper resumes
# the same session on claude2
stub claude '
echo "$(basename "$CLAUDE_CONFIG_DIR") $*" >>"$CALLS"
case "$*" in *--resume*) exit 0 ;; esac
echo "{\"session_id\":\"sess-42\",\"error\":\"rate_limit\",\"last_assistant_message\":\"limit reached|4102444800\"}" | '"$AP"'/lib/on-limit
sleep 10; exit 3'
: >"$CALLS"
"$AP/bin/claude" --model opus "fix the bug" >/dev/null 2>&1
check "rollover: started on claude1" grep -q "^claude1 --model opus fix the bug" "$CALLS"
check "rollover: resumed on claude2 with the flags, not the prompt" grep -q "^claude2 --model opus --resume sess-42 Continue" "$CALLS"
check "rollover: claude2 is active now" [ "$(cat "$AGENT_POOL_DIR/state/active")" = claude2 ]
check "rollover: no handoff left behind" not ls "$AGENT_POOL_DIR"/state/handoff.* 2>/dev/null

# nested inside a claude session: straight through, no account switching
: >"$CALLS"
CLAUDECODE=1 CLAUDE_CONFIG_DIR=$AGENT_POOL_DIR/claude1 "$AP/bin/claude" -p hi >/dev/null 2>&1
check "nested: passes through on the inherited account" grep -q "^claude1 -p hi" "$CALLS"

# status line: records the meters
echo '{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":4102444800}}}' \
    | AGENT_POOL_ACCOUNT=claude2 "$AP/lib/statusline" >"$TMP/line"
check "statusline: shows account and meter" grep -q "claude2.*5h 42%" "$TMP/line"
check "statusline: usage kept for pick" grep -q '"used_percentage": 42' "$AGENT_POOL_DIR/state/claude2.usage.json"

finish
