---
name: sweep
version: 1.0.0
description: |
  Session sweep: finds and removes stale git worktrees across all repos that have a
  .claude/worktrees directory. Defaults to 7-day staleness threshold, archiving
  conversations, and sweeping all worktrees. Branch deletion and temp file cleanup
  are opt-in. Use when asked to "clean stale worktrees", "sweep worktrees",
  "session sweep", "cleanup worktrees", or "remove old worktrees".
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# /sweep — Stale Worktree Session Sweep

You are running the `/sweep` workflow. Clean up stale git worktrees across all
repos that have a `.claude/worktrees` directory.

```bash
mkdir -p ~/.gstack/analytics
echo '{"skill":"sweep","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' >> ~/.gstack/analytics/skill-usage.jsonl 2>/dev/null || true
```

---

## Argument Parsing

Parse the user's invocation arguments. Supported flags and parameters:

| Argument | Default | Description |
|---|---|---|
| `--days N` | `7` | Staleness threshold in days |
| `--archive-conversations` | `true` | Archive Claude sessions linked to removed worktrees |
| `--no-archive` | — | Disable conversation archiving |
| `--delete-branches` | `false` | Delete the local git branch tied to each worktree |
| `--remove-temp` | `false` | Remove node_modules, .cache, logs, tmp, and other temp files inside each worktree |
| `--remove-all` | — | Sweep all stale worktrees without per-worktree confirmation |
| Positional names | — | Only sweep worktrees whose names match these (space-separated) |

**Defaults applied when no flags are given:**
- `DAYS=7`
- `ARCHIVE=true`
- `DELETE_BRANCHES=false`
- `REMOVE_TEMP=false`
- `REMOVE_ALL=false` (prompt per worktree unless `--remove-all` was passed)

Record the resolved values — you will reference them throughout.

---

## Step 1: Discover Repos with Worktrees

Search for repos that have a `.claude/worktrees` directory. Scan common locations:

```bash
# Search under home directory for .claude/worktrees directories (limit depth to avoid hanging)
find "$HOME" -maxdepth 6 -type d -name "worktrees" 2>/dev/null \
  | grep "\.claude/worktrees$" \
  | sort
```

Also check the current directory and its parent:
```bash
for d in "$(pwd)" "$(dirname "$(pwd)")"; do
  [ -d "$d/.claude/worktrees" ] && echo "$d/.claude/worktrees"
done
```

Deduplicate and collect all discovered `.claude/worktrees` paths. For each, the
**repo root** is the directory two levels up (e.g., `/path/to/repo` from
`/path/to/repo/.claude/worktrees`).

If no repos are found, tell the user:
> "No repos with a `.claude/worktrees` directory were found under `$HOME`. Nothing to sweep."

Then stop.

---

## Step 2: Enumerate Worktrees Per Repo

For each discovered repo root:

**2a. List git worktrees** (excludes the main worktree):
```bash
cd <repo-root> && git worktree list --porcelain 2>/dev/null
```

This outputs blocks like:
```
worktree /path/to/worktree
HEAD abc123
branch refs/heads/feature-branch

worktree /path/to/another
HEAD def456
branch refs/heads/other-branch
```

Collect: worktree path, HEAD commit SHA, branch name.

**2b. Cross-reference with `.claude/worktrees`** metadata directory:
```bash
ls -1 <repo-root>/.claude/worktrees/ 2>/dev/null
```

Each entry in `.claude/worktrees/` is either a directory or a JSON/YAML metadata
file referencing a worktree session. Read any metadata files present:
```bash
for f in <repo-root>/.claude/worktrees/*; do
  [ -f "$f" ] && cat "$f"
done
```

Capture any session IDs, conversation IDs, or branch names stored in the metadata.

**2c. Detect orphaned Claude worktree records** — entries in `.claude/worktrees`
that no longer have a corresponding git worktree path. These are always stale
regardless of the `--days` threshold.

---

## Step 3: Staleness Check

For each worktree (from git worktree list), determine if it is stale:

```bash
# Last commit date in the worktree
git -C <worktree-path> log -1 --format="%ct" 2>/dev/null || echo "0"

# Last file modification in worktree (excluding .git)
find <worktree-path> -not -path '*/.git/*' -newer /tmp/sweep-ref-$(($(date +%s) - DAYS*86400)) \
  -type f 2>/dev/null | wc -l
```

A worktree is **stale** when:
- Its most recent git commit is older than `DAYS` days, AND
- No files outside `.git/` have been modified within `DAYS` days

Create the reference timestamp file:
```bash
CUTOFF=$(( $(date +%s) - DAYS * 86400 ))
touch -t $(date -d @$CUTOFF +%Y%m%d%H%M.%S 2>/dev/null || date -r $CUTOFF +%Y%m%d%H%M.%S 2>/dev/null) /tmp/sweep-ref 2>/dev/null || true
```

Also mark as stale: orphaned Claude worktree records with no corresponding git path.

If **positional worktree names** were given, filter to only those whose path
basename or branch name matches one of the given names.

---

## Step 4: Build the Sweep Plan

Assemble the full removal plan before touching anything. For each stale worktree,
compute:

| Field | Value |
|---|---|
| Repo | `<repo-root>` |
| Worktree path | `<absolute-path>` |
| Branch | `<branch-name>` |
| Last commit | `<YYYY-MM-DD>` |
| Age | `<N> days` |
| Claude session | `<session-id>` or `none` |
| Actions | list of what will happen |

Actions depend on resolved flags:
- Always: `git worktree remove --force <path>` + remove `.claude/worktrees/<entry>`
- If `ARCHIVE=true` and session found: archive the linked Claude session
- If `DELETE_BRANCHES=true`: `git branch -D <branch>`
- If `REMOVE_TEMP=true`: remove `node_modules/`, `.cache/`, `*.log`, `tmp/`, `dist/`, `.next/`, `.nuxt/`, `__pycache__/`, `.pytest_cache/`, `target/` (Rust/Java), `vendor/` inside the worktree

Print the full plan as a table. Example:

```
Sweep Plan — 3 stale worktrees found (threshold: 7 days)

REPO: /home/user/git/my-project
  [1] feature/old-auth  →  /worktrees/feature-old-auth  (42 days old)
      Actions: remove worktree, remove .claude entry, archive session sess_abc123
  [2] fix/typo          →  /worktrees/fix-typo           (12 days old)
      Actions: remove worktree, remove .claude entry (no session linked)

REPO: /home/user/git/other-project
  [3] experiment/foo    →  /worktrees/experiment-foo     (orphaned — no git path)
      Actions: remove .claude entry only (worktree path no longer exists)

Flags: --delete-branches=false  --remove-temp=false  --archive=true
```

If **no stale worktrees** are found, tell the user and stop:
> "No stale worktrees found (threshold: N days). Nothing to sweep."

---

## Step 5: Confirm

If `REMOVE_ALL=false`:
  Use AskUserQuestion with the plan summary and options:
  - A) Remove all listed worktrees (recommended)
  - B) Select individually
  - C) Cancel

  If B is chosen, for each worktree ask: Remove `<branch>` from `<repo>`? Y/N

If `REMOVE_ALL=true`:
  Print "Proceeding with removal of all N stale worktrees..." and skip confirmation.

---

## Step 6: Execute Removals

Process each confirmed worktree in order. For each one:

### 6a. Archive Claude session (if ARCHIVE=true and session linked)

Look up the session file in `~/.claude/sessions/` or `~/.claude/history.jsonl`:
```bash
# Check for session directory
ls ~/.claude/sessions/ 2>/dev/null | grep "<session-id>"

# Check history file for conversation references
grep -l "<session-id>" ~/.claude/sessions/ 2>/dev/null
```

Archive by moving the session data to an archive directory:
```bash
ARCHIVE_DIR="$HOME/.claude/archive/sessions"
mkdir -p "$ARCHIVE_DIR"
SESSION_FILE="$HOME/.claude/sessions/<session-id>"
if [ -f "$SESSION_FILE" ]; then
  mv "$SESSION_FILE" "$ARCHIVE_DIR/<session-id>.archived-$(date +%Y%m%d)"
  echo "  Archived session: <session-id>"
fi
```

If the session file is not found, note it but continue (do not fail).

### 6b. Remove temp files (if REMOVE_TEMP=true)

Inside the worktree path, remove common temp/build artifacts:
```bash
WT_PATH="<worktree-path>"
for pattern in node_modules .cache .next .nuxt dist build target __pycache__ .pytest_cache vendor .turbo .parcel-cache; do
  find "$WT_PATH" -maxdepth 3 -name "$pattern" -type d -exec rm -rf {} + 2>/dev/null || true
done
find "$WT_PATH" -maxdepth 4 -name "*.log" -type f -delete 2>/dev/null || true
find "$WT_PATH" -maxdepth 3 -name "tmp" -type d -exec rm -rf {} + 2>/dev/null || true
echo "  Removed temp files from: $WT_PATH"
```

### 6c. Remove the git worktree

If the worktree path exists on disk:
```bash
git -C "<repo-root>" worktree remove --force "<worktree-path>" 2>&1
```

If that fails (e.g., path already gone), fall back to:
```bash
git -C "<repo-root>" worktree prune 2>&1
```

If the worktree path does not exist (orphaned): skip git removal, just prune:
```bash
git -C "<repo-root>" worktree prune 2>&1
```

### 6d. Delete the branch (if DELETE_BRANCHES=true)

```bash
git -C "<repo-root>" branch -D "<branch-name>" 2>&1 || true
echo "  Deleted branch: <branch-name>"
```

Skip if the branch is the currently checked-out branch of the main worktree
(check with `git -C <repo-root> branch --show-current`).

### 6e. Remove the .claude/worktrees entry

```bash
ENTRY="<repo-root>/.claude/worktrees/<entry-name>"
if [ -d "$ENTRY" ]; then
  rm -rf "$ENTRY"
elif [ -f "$ENTRY" ]; then
  rm -f "$ENTRY"
fi
echo "  Removed .claude entry: <entry-name>"
```

---

## Step 7: Final Report

After all removals, print a summary:

```
Sweep complete.

Removed: 3 worktrees
  ✓ feature/old-auth   (my-project)   — worktree removed, session archived
  ✓ fix/typo           (my-project)   — worktree removed
  ✓ experiment/foo     (other-project) — .claude entry removed (was orphaned)

Skipped: 0
Errors:  0

Disk reclaimed: ~<N> MB (approximate)
```

Compute approximate disk reclaimed:
```bash
du -sh "<removed-path>" 2>/dev/null || echo "unknown"
```
(Run before removal in Step 6.)

If any errors occurred during removal, list them clearly and suggest manual
remediation (e.g., `git worktree prune` or `rm -rf <path>`).

---

## Error Handling

- **`git worktree remove` fails:** Try `git worktree prune` + `rm -rf <path>` as fallback. Log error but continue with other worktrees.
- **Session file not found:** Note it, skip archiving, continue.
- **Branch is HEAD of main worktree:** Skip branch deletion for that worktree, warn the user.
- **Permission denied on temp file removal:** Log and skip, continue.
- **`.claude/worktrees` entry is a symlink:** Unlink, don't `rm -rf`.
- **Git repo is bare or corrupted:** Skip that repo, note it in the report.

Never abort the entire sweep because one worktree fails — process all confirmed
worktrees and report errors at the end.

---

## Safety Rules

- Never remove the **main worktree** (the root checkout of the repo).
- Never delete a branch that is checked out in any other active worktree.
  Check: `git -C <repo-root> worktree list | grep "<branch>"`.
- Never archive a session without confirming the session ID matches
  the worktree (avoid archiving the wrong conversation).
- When `--remove-temp` is active, only delete **known artifact directories**
  (the explicit list in Step 6b). Never `rm -rf` the entire worktree path
  without going through `git worktree remove` first.
- Always run `git worktree prune` on the repo after removals to keep
  git's internal state consistent.
