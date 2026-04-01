#!/usr/bin/env bash
# sweep_lib.sh — portable logic extracted from the /sweep skill for unit testing

# Parse /sweep arguments into variables:
#   DAYS, ARCHIVE, DELETE_BRANCHES, REMOVE_TEMP, REMOVE_ALL, WORKTREE_NAMES
parse_args() {
  DAYS=7
  ARCHIVE=true
  DELETE_BRANCHES=false
  REMOVE_TEMP=false
  REMOVE_ALL=false
  WORKTREE_NAMES=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days)        DAYS="$2";          shift 2 ;;
      --no-archive)  ARCHIVE=false;      shift   ;;
      --delete-branches) DELETE_BRANCHES=true; shift ;;
      --remove-temp) REMOVE_TEMP=true;   shift   ;;
      --remove-all)  REMOVE_ALL=true;    shift   ;;
      --*)           echo "Unknown flag: $1" >&2; return 1 ;;
      *)             WORKTREE_NAMES+=("$1"); shift ;;
    esac
  done
}

# Return the most recent epoch across two or more activity signals.
# Args: <epoch1> <epoch2> [epoch3 ...]
latest_epoch() {
  local max=0
  for e in "$@"; do
    [[ "$e" -gt "$max" ]] && max="$e"
  done
  echo "$max"
}

# Return 0 (stale) if a worktree's last *activity* is older than DAYS days.
# Activity = most recent of: worktree dir mtime, .git/worktrees entry mtime,
#            .claude/worktrees entry mtime. Commit date is intentionally excluded
#            because a branch tip can predate the worktree's creation by months.
# Args: <worktree_dir_mtime_epoch> <gitdir_entry_mtime_epoch> <claude_entry_mtime_epoch> <days>
is_stale() {
  local wt_mtime="$1"
  local gitdir_mtime="$2"
  local claude_mtime="$3"
  local days="$4"
  local cutoff=$(( $(date +%s) - days * 86400 ))
  local most_recent
  most_recent=$(latest_epoch "$wt_mtime" "$gitdir_mtime" "$claude_mtime")

  [[ "$most_recent" -lt "$cutoff" ]]
}

# Return 0 if a worktree name matches the filter list (or filter is empty = match all).
# Args: <worktree_name> <filter_name...>
matches_filter() {
  local name="$1"; shift
  local filters=("$@")
  [[ ${#filters[@]} -eq 0 ]] && return 0   # no filter = match all
  for f in "${filters[@]}"; do
    [[ "$name" == "$f" ]] && return 0
  done
  return 1
}

# Return 0 if a path looks like the main worktree (i.e. equals the repo root).
# Args: <worktree_path> <repo_root>
is_main_worktree() {
  local wt_path="${1%/}"
  local repo_root="${2%/}"
  [[ "$wt_path" == "$repo_root" ]]
}

# Return 0 if the current directory is inside the given worktree path.
# Used to prevent sweeping the worktree the user's active session lives in.
# Args: <worktree_path> <current_dir>
session_inside_worktree() {
  local wt_path="${1%/}"
  local current_dir="${2%/}"
  # Match if current_dir equals or is a subdirectory of wt_path
  case "$current_dir" in
    "$wt_path"|"$wt_path"/*) return 0 ;;
  esac
  return 1
}
