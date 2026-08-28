#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
log_file="$tmpdir/calls.log"
mkdir -p "$stub_dir"

cat >"$stub_dir/hyprctl" <<'STUB'
#!/bin/bash
[[ -n $HYPRCTL_DOWN ]] && exit 1
printf '%s\n' "${WORKSPACES_JSON:-[]}"
STUB

cat >"$stub_dir/omarchy-hyprland-workspace-persist" <<'STUB'
#!/bin/bash
if [[ $1 == "--list" ]]; then
  printf '%s' "${KEPT_IDS:-}"
  exit 0
fi
printf 'persist %s\n' "$*" >>"$CALL_LOG"
STUB

cat >"$stub_dir/omarchy-hyprland-workspace-name" <<'STUB'
#!/bin/bash
printf 'name %s\n' "$*" >>"$CALL_LOG"
STUB

chmod +x "$stub_dir"/*

run() {
  CALL_LOG="$log_file" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-add" "$@"
}

: >"$log_file"
output=$(WORKSPACES_JSON='[{"id":1},{"id":2},{"id":-99}]' run)
[[ $output == "6" ]] || fail "the first added workspace follows the bar's fixed 1-5" "$output"
[[ $(cat "$log_file") == "persist 6 on" ]] || fail "the added workspace is kept" "$(cat "$log_file")"
pass "the first added workspace is 6 and is kept, special workspaces ignored"

: >"$log_file"
output=$(WORKSPACES_JSON='[{"id":1},{"id":8}]' run)
[[ $output == "9" ]] || fail "the next workspace follows the highest one Hyprland has" "$output"
pass "the next workspace follows the highest one Hyprland has"

: >"$log_file"
output=$(WORKSPACES_JSON='[{"id":1}]' KEPT_IDS=$'7\n11\n' run)
[[ $output == "12" ]] || fail "a kept workspace Hyprland has not created yet still counts" "$output"
pass "a kept workspace Hyprland has not created yet still counts"

: >"$log_file"
output=$(WORKSPACES_JSON='[{"id":6}]' run --name --widget me.workspaces)
[[ $output == "7" ]] || fail "--name still prints the id" "$output"
[[ $(cat "$log_file") == $'persist 7 on\nname --prompt 7 --widget me.workspaces' ]] ||
  fail "--name keeps the workspace, then asks for its name on the given widget" "$(cat "$log_file")"
pass "--name keeps the workspace, then asks for its name on the given widget"

: >"$log_file"
if HYPRCTL_DOWN=1 run 2>/dev/null; then
  fail "a stopped Hyprland is an error"
fi
[[ ! -s $log_file ]] || fail "a stopped Hyprland adds nothing" "$(cat "$log_file")"
pass "a stopped Hyprland is reported, not guessed around"

if run --sideways 2>/dev/null; then
  fail "an unknown option is rejected"
fi
pass "an unknown option is rejected"
