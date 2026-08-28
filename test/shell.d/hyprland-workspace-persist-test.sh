#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq
require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
log_file="$tmpdir/hyprctl.log"
mkdir -p "$stub_dir" "$home_dir"

cat >"$stub_dir/hyprctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
[[ $1 == "eval" && -n $HYPRCTL_EVAL_FAILS ]] && exit 1
exit 0
STUB

cat >"$stub_dir/omarchy-hyprland-workspace-name" <<'STUB'
#!/bin/bash
[[ $1 == "--list" ]] || exit 1
printf '%s\n' "${WORKSPACE_NAMES:-{\}}"
STUB

chmod +x "$stub_dir"/*

run() {
  HOME="$home_dir" XDG_STATE_HOME="$home_dir/.local/state" HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" \
    "$ROOT/bin/omarchy-hyprland-workspace-persist" "$@"
}

rules_dir="$home_dir/.local/state/omarchy/workspace-layouts"
rule_6="$rules_dir/persistent-6.lua"

: >"$log_file"
run 6
[[ -f $rule_6 ]] || fail "persist saves a rule file for the workspace"
grep -Fx 'hl.workspace_rule({ workspace = "6", persistent = true })' "$rule_6" >/dev/null ||
  fail "persist saves a persistent rule" "$(cat "$rule_6")"
grep -Fx 'eval hl.workspace_rule({ workspace = "6", persistent = true })' "$log_file" >/dev/null ||
  fail "persist applies the rule immediately" "$(cat "$log_file")"
[[ ! -e $rule_6.tmp ]] || fail "persist leaves no temporary file behind"
pass "persist saves and applies a persistent rule"

: >"$log_file"
run 6 off
[[ ! -e $rule_6 ]] || fail "persist off removes the rule file"
grep -Fx 'eval hl.workspace_rule({ workspace = "6", persistent = false })' "$log_file" >/dev/null ||
  fail "persist off lifts the rule immediately" "$(cat "$log_file")"
pass "persist off removes and lifts the rule"

: >"$log_file"
HYPRCTL_EVAL_FAILS=1 run 7
grep -Fx 'keyword workspace 7, persistent:true' "$log_file" >/dev/null ||
  fail "persist falls back to the keyword form when eval is unavailable" "$(cat "$log_file")"
[[ -f $rules_dir/persistent-7.lua ]] || fail "the fallback still saves the rule"
pass "persist falls back to the keyword form when eval is unavailable"

# The bar tile of a named workspace promises SUPER+TAB can reach it. Letting
# the workspace go while the name stays would break that promise quietly.
run 8
: >"$log_file"
if WORKSPACE_NAMES='{"8":"chat"}' run 8 off 2>"$tmpdir/stderr"; then
  fail "persist off refuses a named workspace"
fi
[[ -f $rules_dir/persistent-8.lua ]] || fail "a refused off keeps the rule file"
[[ ! -s $log_file ]] || fail "a refused off applies nothing" "$(cat "$log_file")"
grep -q "forget" "$tmpdir/stderr" || fail "a refused off points at forget" "$(cat "$tmpdir/stderr")"
pass "persist off refuses a named workspace and points at forget"

WORKSPACE_NAMES='{"9":"other"}' run 8 off
[[ ! -e $rules_dir/persistent-8.lua ]] || fail "a name on another workspace does not block off"
pass "only the workspace's own name blocks off"

run 12
run 3
output=$(run --list)
[[ $output == $'3\n7\n12' ]] || fail "--list prints the kept ids in numeric order" "$output"
pass "--list prints the kept ids in numeric order"

for bad in 0 -1 x "" 1.5; do
  if run "$bad" 2>/dev/null; then
    fail "workspace id '$bad' is rejected"
  fi
done
if run 5 sideways 2>/dev/null; then
  fail "only on and off are accepted"
fi
pass "persist validates its arguments"

# The saved rules must come back through the same loader that replays layouts.
HOME="$home_dir" XDG_STATE_HOME="$home_dir/.local/state" OMARCHY_PATH="$ROOT" lua <<'LUA' || fail "saved persistent workspaces load into Hyprland configuration"
local rules = {}

hl = {
  workspace_rule = function(rule)
    table.insert(rules, rule)
  end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.workspace-layouts")

local seen = {}
for _, rule in ipairs(rules) do
  assert(rule.persistent == true, "rule is persistent")
  seen[rule.workspace] = true
end
assert(seen["3"] and seen["7"] and seen["12"], "every saved workspace comes back")
assert(#rules == 3, "no extra rules")
LUA
pass "saved persistent workspaces load into Hyprland configuration"
