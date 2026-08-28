#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
log_file="$tmpdir/calls.log"
mkdir -p "$stub_dir"

for command in omarchy-hyprland-workspace-name omarchy-hyprland-workspace-persist; do
  cat >"$stub_dir/$command" <<STUB
#!/bin/bash
printf '%s\n' "$command \$*" >>"\$CALL_LOG"
STUB
  chmod +x "$stub_dir/$command"
done

run() {
  CALL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-forget" "$@"
}

: >"$log_file"
run 6 --widget me.workspaces
[[ $(cat "$log_file") == $'omarchy-hyprland-workspace-name --clear 6 --widget me.workspaces\nomarchy-hyprland-workspace-persist 6 off' ]] ||
  fail "forget clears the name on the given widget, then lets the workspace go" "$(cat "$log_file")"
pass "forget clears the name first, then lets the workspace go"

: >"$log_file"
for bad in 0 x "" --widget; do
  if run "$bad" 2>/dev/null; then
    fail "workspace id '$bad' is rejected"
  fi
done
[[ ! -s $log_file ]] || fail "a rejected id calls nothing" "$(cat "$log_file")"
pass "forget validates the workspace id before touching anything"
