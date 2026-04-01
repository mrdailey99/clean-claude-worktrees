# clean-claude-worktrees

A Claude Code skill (`/sweep`) that performs a **session sweep** — finding and removing stale git worktrees across all your repos that use Claude Code's worktree workflow.

## What it does

`/sweep` scans your machine for any repo containing a `.claude/worktrees/` directory, identifies worktrees that haven't been touched in N days, shows you a full plan of what will be removed, and cleans everything up — including linked Claude sessions, git branches, and temp/build artifacts.

**Default behavior (no flags):**
- Staleness threshold: **7 days**
- Conversation archiving: **on**
- Branch deletion: **off** (opt-in)
- Temp file removal: **off** (opt-in)
- Confirmation: **per-worktree** (unless `--remove-all`)

---

## Installation

Copy the skill into your Claude Code skills directory:

```bash
# macOS / Linux
cp -r skills/sweep ~/.claude/skills/sweep

# Windows (Git Bash / WSL)
cp -r skills/sweep /c/Users/<your-username>/.claude/skills/sweep
```

That's it. Claude Code picks up skills automatically — no restart needed. The `/sweep` command will be available in your next conversation.

---

## Usage

```
/sweep
```
Run with all defaults: 7-day threshold, archive conversations, prompt per worktree.

```
/sweep --days 14
```
Use a 14-day staleness threshold instead.

```
/sweep --remove-all
```
Skip per-worktree confirmation prompts and remove everything stale in one shot.

```
/sweep --delete-branches
```
Also delete the local git branch tied to each removed worktree.

```
/sweep --remove-temp
```
Also remove build/cache artifacts inside each worktree (`node_modules`, `.cache`, `dist`, `.next`, `target`, `__pycache__`, `*.log`, `tmp`, etc.).

```
/sweep --no-archive
```
Skip archiving Claude sessions (just remove the worktree entries).

```
/sweep feature/old-auth fix/typo
```
Only sweep specific worktrees by name (matched against path basename or branch name).

```
/sweep --days 30 --delete-branches --remove-temp --remove-all
```
Full cleanup: 30-day threshold, delete branches, remove temp files, no confirmation.

---

## Flags reference

| Flag | Default | Description |
|---|---|---|
| `--days N` | `7` | Staleness threshold in days |
| `--remove-all` | off | Skip per-worktree confirmation |
| `--delete-branches` | off | Delete the local git branch for each removed worktree |
| `--remove-temp` | off | Remove build/cache/temp artifacts inside the worktree |
| `--no-archive` | off | Skip archiving linked Claude conversations |
| `<name> ...` | all | Only sweep worktrees matching these names |

---

## How it works

The skill runs 7 steps:

1. **Discover** — scans `$HOME` (up to 6 levels deep) for repos containing `.claude/worktrees/`
2. **Enumerate** — runs `git worktree list` per repo and reads `.claude/worktrees/` metadata to link sessions to worktrees
3. **Staleness check** — a worktree is stale when both its last git commit AND last file modification are older than the threshold. Orphaned Claude entries (no matching git path) are always considered stale.
4. **Build plan** — displays a full table of every worktree to be removed and what actions will be taken, before touching anything
5. **Confirm** — prompts you per worktree (or proceeds automatically with `--remove-all`)
6. **Execute** — for each confirmed worktree, in order:
   - Archive the linked Claude session (if `--archive` is on)
   - Remove temp/build artifacts (if `--remove-temp`)
   - `git worktree remove --force <path>`
   - `git branch -D <branch>` (if `--delete-branches`)
   - Remove the `.claude/worktrees/<entry>`
   - `git worktree prune`
7. **Report** — prints a summary with counts, any errors, and approximate disk reclaimed

### Safety rules

- Never removes the **main worktree** (the root checkout of the repo)
- Never deletes a branch that is currently checked out in any other active worktree
- Never `rm -rf` a worktree path directly — always goes through `git worktree remove` first
- Errors on one worktree do not abort the rest of the sweep
- Orphaned entries (`.claude/worktrees/` records with no matching git path) are cleaned up safely without attempting a git removal

---

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- Git 2.5+ (for worktree support)
- `gh` CLI is not required

---

## License

MIT
