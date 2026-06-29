#!/usr/bin/env bash
# Open the session picker in a popup.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

# The session of a client attached to a prefixed session — i.e. the popup we are
# inside, if any. Empty when invoked from a normal (non-popup) pane.
nested_session() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v p="$prefix" 'index($2, p) == 1 { print $2; exit }'
}

# A client NOT attached to a prefixed session — the outer client that should host
# the picker popup.
host_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v p="$prefix" 'index($2, p) != 1 { print $1; exit }'
}

# The client that pressed the key, passed by the binding as '#{client_name}'.
invoker="${1:-}"

# True if $1 names a client currently attached to a non-prefixed session.
is_live_host() {
  [ -n "$1" ] || return 1
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v c="$1" -v p="$prefix" \
      '$1 == c && index($2, p) != 1 { found = 1 } END { exit !found }'
}

# Pick the client that should host the picker popup.
sess="$(nested_session)"
if [ -n "$sess" ]; then
  # Invoked from inside a session popup. Close it, then reopen on the client that
  # hosted it (recorded as @claude_parent when this popup was opened) — not the
  # invoking client, which is the popup we're about to detach, nor an arbitrary
  # outer client.
  tmux detach-client -s "$sess"
  # Wait until the session is gone
  for _ in $(seq 1 100); do
    [ -z "$(nested_session)" ] && break
    sleep 0.05
  done
  host="$(tmux show-options -gqv @claude_parent 2>/dev/null)"
  is_live_host "$host" || host="$(host_client)"
else
  # Invoked from a normal pane: host on the invoking client so the popup opens on
  # the current session, not an arbitrary one.
  if is_live_host "$invoker"; then
    host="$invoker"
  else
    host="$(host_client)"
  fi
fi
tmux set-option -g @claude_parent "$host"

# Host the picker on the outer client. -c is honored because that client has no
# popup open now; fall back to the default client if none was found.
if [ -n "$host" ]; then
  tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
else
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
fi
