#!/usr/bin/env bash
# Open the session picker in a popup.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

# The client that pressed the key, passed by the binding as '#{client_name}'.
invoker="${1:-}"

# The session a given client is attached to (empty if the client is unknown).
client_session() {
  [ -n "$1" ] || return 0
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v c="$1" '$1 == c { print $2; exit }'
}

# A client NOT attached to a prefixed session — a fallback host for the popup.
host_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v p="$prefix" 'index($2, p) != 1 { print $1; exit }'
}

# True if $1 names a client currently attached to a non-prefixed session.
is_live_host() {
  case "$(client_session "$1")" in
  '' | "$prefix"*) return 1 ;;
  *) return 0 ;;
  esac
}

# Pick the client that should host the picker popup, based on where the *invoking*
# client is — never some other client that merely happens to be in a Claude
# session (that would hijack an unrelated session's popup).
inv_sess="$(client_session "$invoker")"
case "$inv_sess" in
"$prefix"*)
  # Invoked from inside a session popup. Close it, then reopen on the client that
  # hosted it (recorded as @claude_parent when this popup was opened) — not the
  # invoking client, which is the popup we're about to detach.
  tmux detach-client -s "$inv_sess"
  # Wait until the invoking popup is gone.
  for _ in $(seq 1 100); do
    case "$(client_session "$invoker")" in "$prefix"*) sleep 0.05 ;; *) break ;; esac
  done
  host="$(tmux show-options -gqv @claude_parent 2>/dev/null)"
  is_live_host "$host" || host="$(host_client)"
  ;;
*)
  # Invoked from a normal pane: host on the invoking client so the popup opens on
  # the current session, not an arbitrary one.
  if is_live_host "$invoker"; then
    host="$invoker"
  else
    host="$(host_client)"
  fi
  ;;
esac
tmux set-option -g @claude_parent "$host"

# Host the picker on the outer client. -c is honored because that client has no
# popup open now; fall back to the default client if none was found.
if [ -n "$host" ]; then
  tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
else
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
fi
