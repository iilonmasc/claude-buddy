#!/usr/bin/env bash
# buddy-comment Stop hook
# Extracts hidden buddy comment from Claude's response.
# Claude writes: <!-- buddy: *adjusts tophat* nice code -->
# This hook extracts it and updates the status line bubble.
# The HTML comment is invisible in rendered markdown output.

STATE_DIR="$HOME/.claude-buddy"
STATUS_FILE="$STATE_DIR/status.json"

[ -f "$STATUS_FILE" ] || exit 0

INPUT=$(cat)

# Extract last_assistant_message from hook input
MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)
[ -z "$MSG" ] && exit 0

# Extract <!-- buddy: ... --> comment (perl: PCRE lookahead not available in macOS BSD grep)
COMMENT=$(echo "$MSG" | perl -ne 'print $1 if /<!--\s*buddy:\s*(.+?)\s*-->/' | tail -1)
[ -z "$COMMENT" ] && exit 0

mkdir -p "$STATE_DIR"

# Update status.json with the reaction
TMP=$(mktemp)
jq --arg r "$COMMENT" '.reaction = $r' "$STATUS_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$STATUS_FILE"

# Also write reaction file
cat > "$STATE_DIR/reaction.json" <<EOJSON
{"reaction":"$COMMENT","timestamp":$(date +%s%3N),"reason":"turn"}
EOJSON

exit 0
