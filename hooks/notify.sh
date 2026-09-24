#!/usr/bin/env bash
# Claude Code Notification hook: alert when Claude needs attention
# (permission prompt, idle waiting for input, elicitation dialog).
#
# - Inside Ghostty: sends an OSC 9 desktop notification + BEL to the tab's tty.
#   BEL triggers Ghostty's bell-features (attention = dock bounce, title = 🔔 on the tab).
# - Elsewhere: falls back to an osascript notification.

input=$(cat)
message=$(jq -r '.message // "Claude needs your attention"' <<<"$input")
type=$(jq -r '.notification_type // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
project=$(basename "${cwd:-$PWD}")

case "$type" in
  permission_prompt) title="Claude: approval needed" ;;
  idle_prompt)       title="Claude: waiting for input" ;;
  *)                 title="Claude Code" ;;
esac
body="[$project] $message"

# Walk up the process tree and return the OUTERMOST tty, i.e. the Ghostty tab's
# own pty. This matters when claude runs nested (e.g. inside nvim's :terminal),
# where the innermost tty belongs to nvim, not Ghostty.
find_tty() {
  local pid=$PPID tty found=""
  while [[ -n "$pid" && "$pid" -gt 1 ]]; do
    tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -n "$tty" && "$tty" != "??" ]] && found="/dev/$tty"
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  [[ -n "$found" ]] && echo "$found"
}

tty_dev=$(find_tty)

if [[ "$TERM_PROGRAM" == "ghostty" && -n "$tty_dev" && -w "$tty_dev" ]]; then
  # Strip characters that would break the OSC sequence.
  safe=$(printf '%s: %s' "$title" "$body" | tr -d '\007\033;')
  printf '\033]9;%s\007\007' "$safe" >"$tty_dev"
else
  esc() { sed 's/\\/\\\\/g; s/"/\\"/g' <<<"$1"; }
  osascript -e "display notification \"$(esc "$body")\" with title \"$(esc "$title")\" sound name \"Glass\"" >/dev/null 2>&1
fi

exit 0
