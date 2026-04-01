#!/usr/bin/env bash
# test_sweep.sh — unit tests for sweep skill logic
# Usage: bash tests/test_sweep.sh
# Exit code: 0 = all pass, 1 = failures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sweep_lib.sh"

PASS=0
FAIL=0
ERRORS=()

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS  $test_name"
    (( PASS++ )) || true
  else
    echo "  FAIL  $test_name"
    echo "        expected: $expected"
    echo "        actual:   $actual"
    (( FAIL++ )) || true
    ERRORS+=("$test_name")
  fi
}

assert_exit() {
  local test_name="$1" expected_code="$2"
  shift 2
  local actual_code=0
  "$@" || actual_code=$?
  assert_eq "$test_name" "$expected_code" "$actual_code"
}

# ─────────────────────────────────────────────
echo ""
echo "=== parse_args ==="

parse_args
assert_eq "default days"             "7"     "$DAYS"
assert_eq "default archive"          "true"  "$ARCHIVE"
assert_eq "default delete-branches"  "false" "$DELETE_BRANCHES"
assert_eq "default remove-temp"      "false" "$REMOVE_TEMP"
assert_eq "default remove-all"       "false" "$REMOVE_ALL"
assert_eq "default worktree names"   "0"     "${#WORKTREE_NAMES[@]}"

parse_args --days 14
assert_eq "--days 14"  "14"  "$DAYS"

parse_args --no-archive
assert_eq "--no-archive sets ARCHIVE=false"  "false"  "$ARCHIVE"

parse_args --delete-branches
assert_eq "--delete-branches"  "true"  "$DELETE_BRANCHES"

parse_args --remove-temp
assert_eq "--remove-temp"  "true"  "$REMOVE_TEMP"

parse_args --remove-all
assert_eq "--remove-all"  "true"  "$REMOVE_ALL"

parse_args feature/old-auth fix/typo
assert_eq "positional names count"    "2"                "${#WORKTREE_NAMES[@]}"
assert_eq "positional name 0"         "feature/old-auth" "${WORKTREE_NAMES[0]}"
assert_eq "positional name 1"         "fix/typo"         "${WORKTREE_NAMES[1]}"

parse_args --days 30 --delete-branches --remove-temp --remove-all
assert_eq "combined flags: days"              "30"   "$DAYS"
assert_eq "combined flags: delete-branches"  "true" "$DELETE_BRANCHES"
assert_eq "combined flags: remove-temp"      "true" "$REMOVE_TEMP"
assert_eq "combined flags: remove-all"       "true" "$REMOVE_ALL"

# Unknown flag should return non-zero
if parse_args --unknown-flag 2>/dev/null; then
  echo "  FAIL  unknown flag should fail"
  (( FAIL++ )) || true
  ERRORS+=("unknown flag should fail")
else
  echo "  PASS  unknown flag should fail"
  (( PASS++ )) || true
fi

# ─────────────────────────────────────────────
echo ""
echo "=== is_stale ==="

NOW=$(date +%s)
OLD=$(( NOW - 10 * 86400 ))   # 10 days ago
RECENT=$(( NOW - 1 * 86400 )) # 1 day ago

# Both commit and file older than 7 days → stale
assert_exit "both old → stale (exit 0)"     0  is_stale "$OLD"    "$OLD"    7

# Commit old, file recent → not stale
assert_exit "commit old, file recent → not stale (exit 1)"  1  is_stale "$OLD"    "$RECENT" 7

# Commit recent, file old → not stale
assert_exit "commit recent, file old → not stale (exit 1)"  1  is_stale "$RECENT" "$OLD"    7

# Both recent → not stale
assert_exit "both recent → not stale (exit 1)"  1  is_stale "$RECENT" "$RECENT" 7

# 1 second inside the threshold → not stale
JUST_INSIDE=$(( NOW - 7 * 86400 + 2 ))
assert_exit "1s inside threshold → not stale (exit 1)"  1  is_stale "$JUST_INSIDE" "$JUST_INSIDE" 7

# 1 hour outside the threshold → stale
JUST_OUTSIDE=$(( NOW - 7 * 86400 - 3600 ))
assert_exit "1h outside threshold → stale (exit 0)"    0  is_stale "$JUST_OUTSIDE" "$JUST_OUTSIDE" 7

# Custom threshold
assert_exit "custom 30-day threshold: 20-day-old worktree → not stale"  1  is_stale $(( NOW - 20*86400 )) $(( NOW - 20*86400 )) 30
assert_exit "custom 30-day threshold: 31-day-old worktree → stale"      0  is_stale $(( NOW - 31*86400 )) $(( NOW - 31*86400 )) 30

# ─────────────────────────────────────────────
echo ""
echo "=== matches_filter ==="

assert_exit "empty filter matches anything"               0  matches_filter "feature/foo"
assert_exit "exact match"                                 0  matches_filter "feature/foo" "feature/foo"
assert_exit "match in list"                               0  matches_filter "fix/bar"     "feature/foo" "fix/bar"
assert_exit "no match in list"                            1  matches_filter "experiment"  "feature/foo" "fix/bar"
assert_exit "partial name not a match"                    1  matches_filter "feature/foo-extra" "feature/foo"
assert_exit "single-item list, no match"                  1  matches_filter "other"       "feature/foo"

# ─────────────────────────────────────────────
echo ""
echo "=== is_main_worktree ==="

assert_exit "identical paths → main worktree"             0  is_main_worktree "/home/user/repo"           "/home/user/repo"
assert_exit "trailing slash normalised → main worktree"   0  is_main_worktree "/home/user/repo/"          "/home/user/repo"
assert_exit "subdirectory → not main"                     1  is_main_worktree "/home/user/repo/worktrees/branch" "/home/user/repo"
assert_exit "sibling dir → not main"                      1  is_main_worktree "/home/user/repo2"          "/home/user/repo"
assert_exit "empty path vs root → not main"               1  is_main_worktree ""                          "/home/user/repo"

# ─────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  exit 1
fi

echo "All tests passed."
exit 0
