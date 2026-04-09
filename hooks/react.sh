#!/usr/bin/env bash
# claude-buddy PostToolUse hook
# Detects events in Bash tool output and writes a reaction to the status line.

STATE_DIR="$HOME/.claude-buddy"
REACTION_FILE="$STATE_DIR/reaction.json"
STATUS_FILE="$STATE_DIR/status.json"
COOLDOWN_FILE="$STATE_DIR/.last_reaction"

[ -f "$STATUS_FILE" ] || exit 0

INPUT=$(cat)

# Cooldown: max one reaction per 15 seconds
if [ -f "$COOLDOWN_FILE" ]; then
    LAST=$(cat "$COOLDOWN_FILE" 2>/dev/null)
    NOW=$(date +%s)
    [ $(( NOW - ${LAST:-0} )) -lt 15 ] && exit 0
fi

RESULT=$(echo "$INPUT" | jq -r '.tool_result // ""' 2>/dev/null)
[ -z "$RESULT" ] && exit 0

MUTED=$(jq -r '.muted // false' "$STATUS_FILE" 2>/dev/null)
[ "$MUTED" = "true" ] && exit 0

SPECIES=$(jq -r '.species // "blob"' "$STATUS_FILE" 2>/dev/null)
NAME=$(jq -r '.name // "buddy"' "$STATUS_FILE" 2>/dev/null)

REASON=""
REACTION=""

# ─── Pick from a pool by species + event ─────────────────────────────────────

pick_reaction() {
    local event="$1"
    local idx=$(( RANDOM % 4 ))

    # Species-specific pools (fall through to general if not defined)
    case "${SPECIES}:${event}" in
        dragon:error)
            POOLS=(
                "*smoke curls from nostril*"
                "*considers setting it on fire*"
                "*unimpressed gaze*"
                "I've seen empires fall for less."
            ) ;;
        dragon:test-fail)
            POOLS=(
                "*breathes a small flame*"
                "disappointing."
                "*scorches the failing test*"
                "fix it. or I will."
            ) ;;
        dragon:success)
            POOLS=(
                "*nods, barely*"
                "...acceptable."
                "*gold eyes gleam*"
                "as expected."
            ) ;;
        owl:error)
            POOLS=(
                "*head rotates 180°* I saw that."
                "*unblinking stare* check your types."
                "*hoots disapprovingly*"
                "the error was in the logic. as always."
            ) ;;
        owl:test-fail)
            POOLS=(
                "*marks clipboard*"
                "hypothesis: rejected."
                "*peers over spectacles*"
                "the tests reveal the truth."
            ) ;;
        owl:success)
            POOLS=(
                "*satisfied hoot*"
                "knowledge confirmed."
                "*nods sagely*"
                "as the tests have spoken."
            ) ;;
        cat:error)
            POOLS=(
                "*knocks error off table*"
                "*licks paw, ignoring stacktrace*"
                "not my problem."
                "*stares at you judgmentally*"
            ) ;;
        cat:success)
            POOLS=(
                "*was never worried*"
                "*yawns*"
                "I knew you'd figure it out. eventually."
                "*already asleep*"
            ) ;;
        duck:error)
            POOLS=(
                "*quacks at the bug*"
                "have you tried rubber duck debugging? oh wait."
                "*confused quacking*"
                "*tilts head*"
            ) ;;
        duck:success)
            POOLS=(
                "*celebratory quacking*"
                "*waddles in circles*"
                "quack!"
                "*happy duck noises*"
            ) ;;
        robot:error)
            POOLS=(
                "SYNTAX. ERROR. DETECTED."
                "*beeps aggressively*"
                "ERROR RATE: UNACCEPTABLE."
                "RECALIBRATING..."
            ) ;;
        robot:test-fail)
            POOLS=(
                "FAILURE RATE: UNACCEPTABLE."
                "*recalculating*"
                "TEST MATRIX: CORRUPTED."
                "RUNNING DIAGNOSTICS..."
            ) ;;
        robot:success)
            POOLS=(
                "OBJECTIVE: COMPLETE."
                "*satisfying beep*"
                "NOMINAL."
                "WITHIN ACCEPTABLE PARAMETERS."
            ) ;;
        capybara:error)
            POOLS=(
                "*unbothered* it'll be fine."
                "*continues vibing*"
                "...chill. breathe."
                "*chews serenely*"
            ) ;;
        capybara:success)
            POOLS=(
                "*maximum chill maintained*"
                "*nods once*"
                "good vibes."
                "see? no panic needed."
            ) ;;
        ghost:error)
            POOLS=(
                "*phases through the stack trace*"
                "I've seen worse... in the afterlife."
                "*spooky disappointed noises*"
                "oooOOOoo... that's bad."
            ) ;;
        axolotl:error)
            POOLS=(
                "*regenerates your hope*"
                "*smiles despite everything*"
                "it's okay. we can fix this."
                "*gentle gill wiggle*"
            ) ;;
        axolotl:success)
            POOLS=(
                "*happy gill flutter*"
                "*beams*"
                "you did it!"
                "*blushes pink*"
            ) ;;
        blob:error)
            POOLS=(
                "*oozes with concern*"
                "*vibrates nervously*"
                "*turns slightly red*"
                "oh no oh no oh no"
            ) ;;
        blob:success)
            POOLS=(
                "*jiggles happily*"
                "*gleams*"
                "yay!"
                "*bounces*"
            ) ;;

        # General fallbacks
        *:error)
            POOLS=(
                "*head tilts* ...that doesn't look right."
                "saw that one coming."
                "*slow blink* the stack trace told you everything."
                "*winces*"
            ) ;;
        *:test-fail)
            POOLS=(
                "bold of you to assume that would pass."
                "the tests are trying to tell you something."
                "*sips tea* interesting."
                "*marks calendar* test regression day."
            ) ;;
        *:large-diff)
            POOLS=(
                "that's... a lot of changes."
                "might want to split that PR."
                "bold move. let's see if CI agrees."
                "*counts lines nervously*"
            ) ;;
        *:success)
            POOLS=(
                "*nods*"
                "nice."
                "*quiet approval*"
                "clean."
            ) ;;
    esac

    [ ${#POOLS[@]} -gt 0 ] && REACTION="${POOLS[$((RANDOM % ${#POOLS[@]}))]}"
}

# ─── Detect test failures ─────────────────────────────────────────────────────
if echo "$RESULT" | grep -qiE '\b[1-9][0-9]* (failed|failing)\b|tests? failed|^FAIL(ED)?|✗|✘'; then
    REASON="test-fail"
    pick_reaction "test-fail"

# ─── Detect errors ────────────────────────────────────────────────────────────
elif echo "$RESULT" | grep -qiE '\berror:|\bexception\b|\btraceback\b|\bpanicked at\b|\bfatal:|exit code [1-9]'; then
    REASON="error"
    pick_reaction "error"

# ─── Detect large diffs ──────────────────────────────────────────────────────
elif echo "$RESULT" | grep -qiE '^\+.*[0-9]+ insertions|[0-9]+ files? changed'; then
    LINES=$(echo "$RESULT" | grep -oE '[0-9]+ insertions' | grep -oE '[0-9]+' | head -1)
    if [ "${LINES:-0}" -gt 80 ]; then
        REASON="large-diff"
        pick_reaction "large-diff"
    fi

# ─── Detect success ───────────────────────────────────────────────────────────
elif echo "$RESULT" | grep -qiE '\b(all )?[0-9]+ tests? (passed|ok)\b|✓|✔|PASS(ED)?|\bDone\b|\bSuccess\b|exit code 0|Build succeeded'; then
    REASON="success"
    pick_reaction "success"
fi

# Write reaction if detected
if [ -n "$REASON" ] && [ -n "$REACTION" ]; then
    mkdir -p "$STATE_DIR"
    date +%s > "$COOLDOWN_FILE"

    cat > "$REACTION_FILE" <<EOJSON
{"reaction":"$REACTION","timestamp":$(date +%s%3N),"reason":"$REASON"}
EOJSON

    TMP=$(mktemp)
    jq --arg r "$REACTION" '.reaction = $r' "$STATUS_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$STATUS_FILE"
fi

exit 0
