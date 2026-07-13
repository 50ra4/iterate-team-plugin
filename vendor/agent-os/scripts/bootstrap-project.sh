#!/usr/bin/env bash
# bootstrap-project.sh
#
# Install the Adaptive Agent OS into a target project: copies the
# project-adapter skeleton (.agent-os/, CLAUDE.md/AGENTS.md), the
# per-assistant skills/agents, vendors the canonical skills library, and
# vendors the global principle files (GLOBAL_AGENTS.md / GLOBAL_CLAUDE.md).
#
# This script only ever writes files that belong to its own known
# manifest (never arbitrary user files) and never deletes anything
# (--reset-adapter moves files into a timestamped backup, it does not
# remove them).
#
# Symlink safety principle (applies to every copy, every directory this
# script creates, and every --reset-adapter backup move): a path is only
# ever operated on if (1) no existing component of it is a symlink, and
# (2) its physical resolution (pwd -P) stays inside the target project /
# adapter root. Any violation is refused explicitly -- nothing is ever
# written, mkdir'd, or moved outside the target as a side effect, even
# when the refused write itself leaves no other trace.
#
# Ownership split:
#   - OS-owned (regenerable, --force overwrites them): .claude/skills/,
#     .claude/agents/, .codex/agents/, .agents/skills/, the vendored
#     .agent-os/skills/, and the vendored .agent-os/GLOBAL_AGENTS.md /
#     .agent-os/GLOBAL_CLAUDE.md.
#   - Protected (project-owned learning state, --force never overwrites
#     these): the 8 adapter state files under <target>/.agent-os/*.md
#     (project-profile, learned-rules, failure-log, review-feedback-log,
#     evals, command-map, architecture-map, risk-map) and the root entry
#     files <target>/CLAUDE.md and <target>/AGENTS.md. Use
#     --reset-adapter to explicitly replace them (with an automatic
#     backup first).
#
# .agent-os/rules/ (the optional split-rule layout) and .agent-os/backup-*/
# directories are never written to, read from, or deleted by this script.
set -euo pipefail

# Resolve paths relative to this script's location so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_OS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap-project.sh --target <dir> --for claude|codex|both [--force] [--reset-adapter]

Install the Agent OS into a target project directory.

Options:
  --target <dir>     Path to the project to install into (must already exist).
  --for <which>       Which assistant(s) to wire up: claude, codex, or both.
  --force             Overwrite OS-owned files that already exist (skills,
                      agents, vendored .agent-os/skills/, GLOBAL_*.md).
                      Never overwrites project-owned adapter state: the 8
                      .agent-os/*.md state files (project-profile,
                      learned-rules, failure-log, review-feedback-log,
                      evals, command-map, architecture-map, risk-map) and
                      the root CLAUDE.md/AGENTS.md entry files. Existing
                      protected files print a PROTECTED: line and are left
                      untouched.
  --reset-adapter     Explicitly reset project-owned adapter state: every
                      existing protected file (the 8 .agent-os/*.md state
                      files plus root CLAUDE.md/AGENTS.md) is moved into
                      .agent-os/backup-<timestamp>/ and fresh starter
                      copies are installed in their place. Does not imply
                      --force for OS-owned files.
  --help              Show this help text and exit.

Symlink safety: this script never writes through or replaces a symlinked
destination, never creates a directory through a symlinked path
component, and never moves a --reset-adapter backup through one either.
Before any write, mkdir, or move, every existing directory component of
the path in question must not be a symlink, and the path's physical
(symlink-resolved) resolution must stay inside the target project /
adapter root -- otherwise the operation is refused outright rather than
silently redirected. Top-level Agent OS directories under the target
(.agent-os, .claude, .codex, .agents) are checked for this up front,
before any mode does any work; individual copies additionally refuse
with a "BLOCKED (symlink):" line (counted separately in the summary,
with no directories left behind outside the target as a side effect);
--reset-adapter refuses with an ERROR and exits 1, having moved nothing.
Remove the symlink manually if you want a regular file/directory
installed there.

Examples:
  bootstrap-project.sh --target ../my-app --for claude
  bootstrap-project.sh --target ../my-app --for both --force
  bootstrap-project.sh --target ../my-app --for both --reset-adapter
EOF
}

# ---- Argument parsing -------------------------------------------------
TARGET=""
FOR=""
FORCE=0
RESET_ADAPTER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --target)
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires a value" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    --for)
      [[ $# -ge 2 ]] || { echo "ERROR: --for requires a value" >&2; exit 2; }
      FOR="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --reset-adapter)
      RESET_ADAPTER=1
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$TARGET" || -z "$FOR" ]]; then
  echo "ERROR: --target and --for are required" >&2
  usage >&2
  exit 2
fi

case "$FOR" in
  claude|codex|both) ;;
  *)
    echo "ERROR: --for must be one of: claude, codex, both (got: $FOR)" >&2
    exit 2
    ;;
esac

if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: target directory does not exist: $TARGET" >&2
  exit 1
fi

TARGET_ABS="$(cd "$TARGET" && pwd)"
PROJECT_NAME="$(basename "$TARGET_ABS")"
# Physical (symlink-resolved) path of the target, used by copy_file()'s
# containment check to detect a symlinked intermediate directory that
# would otherwise silently redirect a write outside the target project.
TARGET_PHYS="$(cd "$TARGET_ABS" && pwd -P)"

# ---- Startup symlink gate (defense layer 1) ---------------------------
# Refuse outright, before any write/mkdir/move of any kind and for every
# mode (plain install, --force, --reset-adapter), if a top-level Agent
# OS directory under the target is itself a symlink. Without this, a
# symlinked .agent-os (or .claude/.codex/.agents) would let copy_file()
# resolve destinations, and reset_adapter() resolve its backup_dir,
# through the link -- silently relocating adapter files (even root
# CLAUDE.md/AGENTS.md, via --reset-adapter) outside the project before
# any per-write guard runs. copy_file()'s per-write containment check
# and reset_adapter()'s own checks are defense layer 2, for directories
# and components that do not exist yet at startup and only come into
# being once the script itself starts creating them.
for _ao_top_dir in .agent-os .claude .codex .agents; do
  _ao_top_path="$TARGET_ABS/$_ao_top_dir"
  if [[ -L "$_ao_top_path" ]]; then
    echo "ERROR: $_ao_top_path is a symlink; refusing to operate on a target whose Agent OS directories are symlinked" >&2
    exit 1
  fi
done
unset _ao_top_dir _ao_top_path

# PROJECT_NAME escaped for safe use as a sed replacement string: a target
# directory basename containing &, /, or \ would otherwise break (or
# misbehave in) the {{PROJECT_NAME}} substitution in apply_project_name().
PROJECT_NAME_ESCAPED="$(printf '%s' "$PROJECT_NAME" | sed 's/[&/\]/\\&/g')"

# The 8 project-owned adapter state files (relative to <target>/.agent-os/,
# without the .md extension). Must match project-adapter/.agent-os/*.md and
# validate-agent-os.sh's ADAPTER_FILES list.
ADAPTER_STATE_FILES=(project-profile learned-rules failure-log review-feedback-log evals command-map architecture-map risk-map)

# ---- Bookkeeping -------------------------------------------------------
INSTALLED_COUNT=0
SKIPPED_COUNT=0
PROTECTED_COUNT=0
BACKED_UP_COUNT=0
BLOCKED_COUNT=0
INSTALLED_LIST=()
SKIPPED_LIST=()
PROTECTED_LIST=()
BACKED_UP_LIST=()
BLOCKED_LIST=()
BACKUP_DIR=""
LAST_ACTION=""

# Set by ensure_reset_backup_dir() to the final backup directory path it
# created for the current --reset-adapter run (see below; may be a
# suffixed variant of the timestamped name it was first called with).
# Reset to "" at the top of reset_adapter() so a stale value from an
# earlier run (relevant only if reset_adapter() were ever invoked more
# than once in a single script execution) can't leak into a new one.
RESET_BACKUP_DIR_FINAL=""

warn() { echo "WARN: $*"; }
info() { echo "INFO: $*"; }

# Set by safe_mkdir_within_target() on failure to the specific path that
# triggered the refusal (a symlinked component, or the final resolved
# path if the containment check itself failed), for use in caller error
# messages.
SAFE_MKDIR_FAIL_PATH=""

# Create directory $1 -- which must be TARGET_ABS itself or a path
# beneath it -- one path component at a time, starting from TARGET_ABS,
# refusing to proceed the moment any existing component turns out to be
# a symlink. This replaces a plain `mkdir -p` followed by a containment
# check: `mkdir -p` walks and creates every missing component in one
# call *before* anything can be checked, so a symlinked intermediate
# component still causes directories to be created outside the target
# as a side effect even when the eventual write is refused. Walking and
# checking component-by-component means no directory is ever created
# outside the target, full stop -- a refused destination leaves no
# trace at all.
#
# Used both for a copy_file() destination's parent directory and for
# --reset-adapter's backup directory (reset_adapter() below), so the
# same guarantee applies to both.
#
# Returns 0 and leaves $1 created on success. Returns 1 and creates
# nothing further on failure, with SAFE_MKDIR_FAIL_PATH set.
safe_mkdir_within_target() {
  local dir="$1"
  SAFE_MKDIR_FAIL_PATH=""

  local rel="${dir#"$TARGET_ABS"}"
  rel="${rel#/}"

  local cur="$TARGET_ABS"
  if [[ -n "$rel" ]]; then
    local part
    local IFS=/
    for part in $rel; do
      [[ -z "$part" ]] && continue
      cur="$cur/$part"
      if [[ -L "$cur" ]]; then
        SAFE_MKDIR_FAIL_PATH="$cur"
        return 1
      fi
      if [[ ! -e "$cur" ]]; then
        mkdir "$cur" || { SAFE_MKDIR_FAIL_PATH="$cur"; return 1; }
      fi
    done
  fi

  # Belt-and-suspenders: after the component walk, the directory's
  # physical (symlink-resolved) path must still be the target directory
  # itself or a descendant of it.
  local phys
  phys="$(cd "$dir" && pwd -P)" || { SAFE_MKDIR_FAIL_PATH="$dir"; return 1; }
  if [[ "$phys" != "$TARGET_PHYS" && "$phys" != "$TARGET_PHYS"/* ]]; then
    SAFE_MKDIR_FAIL_PATH="$phys"
    return 1
  fi
  return 0
}

# Copy a single file to a destination path, honoring --force / skip /
# protected rules. Sets LAST_ACTION to "installed", "skipped", "protected",
# or "blocked".
#
# protected=1 marks a file as project-owned adapter state: if it already
# exists and --force was passed, it is preserved (never overwritten) and a
# PROTECTED: line is printed instead. Without --force, or when the file
# does not yet exist, behavior is identical to protected=0.
#
# Symlink safety (checked FIRST, before protected/exists logic, so a
# symlinked protected file is reported as BLOCKED rather than silently
# PROTECTED): if $dest already exists and is itself a symlink, this
# script refuses to write through or replace it -- plain `cp` would
# follow the link and overwrite whatever it points at, possibly outside
# the target project. It also refuses if a directory component of $dest
# is a symlink that resolves outside the target project (a symlinked
# parent directory silently redirecting the write).
copy_file() {
  local src="$1"
  local dest="$2"
  local protected="${3:-0}"

  if [[ ! -f "$src" ]]; then
    warn "source file missing, skipping: $src"
    LAST_ACTION="skipped"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    SKIPPED_LIST+=("$dest (source missing)")
    return
  fi

  if [[ -L "$dest" ]]; then
    echo "BLOCKED (symlink): destination is a symlink; refusing to write through or replace it: $dest (remove the symlink manually if you want a regular file installed here)"
    LAST_ACTION="blocked"
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    BLOCKED_LIST+=("$dest (destination is a symlink)")
    return
  fi

  if [[ -e "$dest" ]]; then
    if [[ "$protected" -eq 1 && "$FORCE" -eq 1 ]]; then
      echo "PROTECTED: preserving project-owned state, not overwritten by --force: $dest (run with --reset-adapter to replace it; a backup is made automatically)"
      LAST_ACTION="protected"
      PROTECTED_COUNT=$((PROTECTED_COUNT + 1))
      PROTECTED_LIST+=("$dest")
      return
    fi
    if [[ "$FORCE" -ne 1 ]]; then
      warn "already exists, skipping (use --force to overwrite): $dest"
      LAST_ACTION="skipped"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      SKIPPED_LIST+=("$dest")
      return
    fi
    # protected=0 and --force was passed: fall through and overwrite.
  fi

  # Create the destination's parent directory component-by-component,
  # refusing (with no directories left behind outside the target, even
  # in the refused case) if any existing or newly-needed component is a
  # symlink or resolves outside the target project. This catches a
  # symlinked intermediate directory (e.g. .claude/skills -> /somewhere/
  # else, possibly several levels below the top-level Agent OS dirs the
  # startup gate already checked) that the -L check on $dest alone would
  # miss, since $dest itself may not exist yet even though a parent
  # component does.
  if ! safe_mkdir_within_target "$(dirname "$dest")"; then
    echo "BLOCKED (symlink): a symlinked parent directory redirected this write outside the target project: $dest (blocked at: $SAFE_MKDIR_FAIL_PATH); refusing to write. Remove the symlink manually if you want a regular directory here."
    LAST_ACTION="blocked"
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    BLOCKED_LIST+=("$dest (symlinked parent directory escapes target)")
    return
  fi

  cp "$src" "$dest"
  LAST_ACTION="installed"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  INSTALLED_LIST+=("$dest")
}

# Recursively copy all files under a source directory into a destination
# directory, preserving relative structure, file by file (so per-file
# skip/force/protected rules apply even inside vendored skill directories).
copy_dir_contents() {
  local src_dir="$1"
  local dest_dir="$2"
  local protected="${3:-0}"

  if [[ ! -d "$src_dir" ]]; then
    warn "source directory missing, skipping: $src_dir"
    return
  fi

  local rel
  while IFS= read -r file; do
    rel="${file#"$src_dir"/}"
    copy_file "$file" "$dest_dir/$rel" "$protected"
  done < <(find "$src_dir" -type f | sort)
}

# Copy top-level files matching a glob from a source dir into a dest dir
# (non-recursive; used for claude/agents/*.md and codex/agents/*.toml).
copy_flat_glob() {
  local src_dir="$1"
  local dest_dir="$2"
  local pattern="$3"

  if [[ ! -d "$src_dir" ]]; then
    warn "source directory missing, skipping: $src_dir"
    return
  fi

  shopt -s nullglob
  local matched=0
  local f
  for f in "$src_dir"/$pattern; do
    matched=1
    copy_file "$f" "$dest_dir/$(basename "$f")"
  done
  shopt -u nullglob

  if [[ "$matched" -eq 0 ]]; then
    info "no files matching '$pattern' in $src_dir yet, nothing to copy"
  fi
}

# Replace the {{PROJECT_NAME}} placeholder in a copied file, in place.
# Only ever run on files this script just installed (the copies), never
# on arbitrary user files. Uses PROJECT_NAME_ESCAPED (computed once above)
# rather than PROJECT_NAME directly, so a target directory basename
# containing sed-special characters (&, /, \) is substituted literally
# instead of corrupting or breaking the substitution.
apply_project_name() {
  local file="$1"
  # Defense in depth: copy_file() already refuses to write through a
  # symlinked destination, so this should never see one; guard anyway.
  [[ -L "$file" ]] && return
  [[ -f "$file" ]] || return
  sed -i.bak "s/{{PROJECT_NAME}}/$PROJECT_NAME_ESCAPED/g" "$file"
  rm -f "$file.bak"
}

# Apply {{PROJECT_NAME}} substitution to whichever of the 8 adapter state
# files under <target>/.agent-os/ were FRESHLY installed by the
# copy_dir_contents call just above (never one that already existed --
# PROTECTED/skipped files are never rewritten, so a rerun with --force
# after hand-editing learned-rules.md, for instance, leaves it intact).
# copy_file() only appends a destination path to INSTALLED_LIST when it
# actually just copied a new file there (LAST_ACTION="installed"); a
# protected file that already existed is recorded as "protected" or
# "skipped" instead and never lands in INSTALLED_LIST, which is exactly
# the distinction this needs.
apply_project_name_to_fresh_adapter_state_files() {
  local f dest item found
  for f in "${ADAPTER_STATE_FILES[@]}"; do
    dest="$TARGET_ABS/.agent-os/$f.md"
    found=0
    for item in "${INSTALLED_LIST[@]:-}"; do
      if [[ "$item" == "$dest" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" -eq 1 ]]; then
      apply_project_name "$dest"
    fi
  done
  # Explicit success return: this function is invoked as a bare statement
  # (not inside an if/&&), and under `set -e` a function's own exit
  # status is whatever its last executed command returned -- without
  # this, a run where the final ADAPTER_STATE_FILES entry was NOT freshly
  # installed would end on a false `[[ ... ]]` test (from the last loop
  # iteration) and abort the whole script.
  return 0
}

VENDORED=0
vendor_canonical_skills() {
  [[ "$VENDORED" -eq 1 ]] && return
  VENDORED=1

  local vendor_dir="$TARGET_ABS/.agent-os/skills"
  if [[ -d "$vendor_dir" ]] && [[ -n "$(find "$vendor_dir" -mindepth 1 -maxdepth 1 2>/dev/null)" ]] && [[ "$FORCE" -ne 1 ]]; then
    warn "canonical skills already vendored, skipping (use --force to refresh): $vendor_dir"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    SKIPPED_LIST+=("$vendor_dir (already vendored)")
    return
  fi

  copy_dir_contents "$AGENT_OS_ROOT/skills" "$vendor_dir"
}

# Ensure the --reset-adapter backup directory for the current run is a
# freshly-created directory that is safe to move into, and never a
# pre-existing one.
#
# Called with a candidate base path (the timestamped
# .agent-os/backup-<ts> name); on the first call this run, resolves a
# final path and creates it via safe_mkdir_within_target() (the same
# component-walking + containment guard copy_file() uses), then remembers
# it in RESET_BACKUP_DIR_FINAL. Subsequent calls in the same run
# (ensure_reset_backup_dir() is called once per protected file) are a
# no-op: they see RESET_BACKUP_DIR_FINAL already set and return
# immediately without re-deriving anything, so the same directory is
# reused for every file backed up in this run. Callers must read back
# RESET_BACKUP_DIR_FINAL after calling this (the candidate they passed in
# may not be the final path -- see below) and use that for every mv and
# for the final BACKUP_DIR summary value.
#
# Two things the candidate path must never be treated as safe to use:
#
#   1. A symlink. Checked FIRST, with -L, before any -d/-e test that
#      would dereference it -- a symlink here (e.g. planted by an
#      attacker at the exact timestamped name this run will compute) is
#      hostile: following it would let `mv` relocate protected files
#      outside the target. This is a hard error, not worked around by
#      trying another name; the same -L-first check applies to every
#      suffixed candidate below, so a symlink at any of them also aborts
#      immediately.
#   2. An existing regular directory or file (e.g. a leftover backup from
#      an earlier run, or one created by a run in the same second). Never
#      reused and never moved into -- `mv`-ing into it could silently
#      overwrite same-named files already there. Instead, -2, -3, ... is
#      appended to the base name until an unused, non-symlink name is
#      found, and an INFO line notes the adjustment.
#
# Exits 1 immediately -- before any mv -- on any symlink or containment
# violation, so a violation here leaves nothing moved.
ensure_reset_backup_dir() {
  local base="$1"

  # Already resolved and created earlier in this run: reuse it, nothing
  # left to do.
  [[ -n "$RESET_BACKUP_DIR_FINAL" ]] && return 0

  local candidate="$base"
  local suffix=1
  while :; do
    if [[ -L "$candidate" ]]; then
      echo "ERROR: refusing --reset-adapter: $candidate is a symlink; refusing to use a symlinked path (or work around it by picking another name) as the backup directory; nothing moved" >&2
      exit 1
    fi
    if [[ -e "$candidate" ]]; then
      suffix=$((suffix + 1))
      candidate="${base}-${suffix}"
      continue
    fi
    break
  done

  if [[ "$candidate" != "$base" ]]; then
    info "reset-adapter: backup directory $base already exists, using $candidate instead"
  fi

  if ! safe_mkdir_within_target "$candidate"; then
    echo "ERROR: refusing --reset-adapter: could not safely create backup directory $candidate (blocked at: $SAFE_MKDIR_FAIL_PATH); nothing moved" >&2
    exit 1
  fi

  RESET_BACKUP_DIR_FINAL="$candidate"
}

# ---- --reset-adapter: back up existing protected files, then let the ----
# ---- normal install steps below install fresh copies in their place. ----
reset_adapter() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local ao_dir="$TARGET_ABS/.agent-os"
  local backup_dir="$ao_dir/backup-$ts"
  local any=0
  local f src was_symlink note

  # Fresh state for this run: see ensure_reset_backup_dir()'s comment for
  # why this must start empty each time reset_adapter() runs.
  RESET_BACKUP_DIR_FINAL=""

  # Defense layer 2 (beneath the startup gate above, which already
  # refuses if .agent-os itself is a symlink before reset_adapter() is
  # ever called): re-verify here, right before doing anything else, that
  # if .agent-os exists it is not a symlink and its physical
  # (symlink-resolved) path is exactly TARGET_PHYS/.agent-os -- not
  # somewhere else reached through a symlinked ancestor component. This
  # runs before the backup directory is created and before any file is
  # moved, so a violation leaves the target and the backup_dir's
  # eventual location completely untouched.
  if [[ -e "$ao_dir" ]]; then
    if [[ -L "$ao_dir" ]]; then
      echo "ERROR: refusing --reset-adapter: $ao_dir is a symlink; nothing moved" >&2
      exit 1
    fi
    local ao_phys
    ao_phys="$(cd "$ao_dir" && pwd -P)"
    if [[ "$ao_phys" != "$TARGET_PHYS/.agent-os" ]]; then
      echo "ERROR: refusing --reset-adapter: $ao_dir resolves to $ao_phys, outside $TARGET_PHYS/.agent-os (a symlinked ancestor directory redirected it); nothing moved" >&2
      exit 1
    fi
  fi

  # Note: if a protected file is itself a symlink, `mv` moves the link
  # entry itself (it does not follow it and does not write through it),
  # so this is safe -- provided its parent directory (verified above, or
  # TARGET_ABS itself for the root CLAUDE.md/AGENTS.md case) has already
  # passed the checks above. The backup list simply calls out that it
  # was a symlink so the summary is honest about what got backed up.
  for f in "${ADAPTER_STATE_FILES[@]}"; do
    src="$TARGET_ABS/.agent-os/$f.md"
    if [[ -f "$src" || -L "$src" ]]; then
      was_symlink=0
      [[ -L "$src" ]] && was_symlink=1
      ensure_reset_backup_dir "$backup_dir"
      backup_dir="$RESET_BACKUP_DIR_FINAL"
      mv "$src" "$backup_dir/$f.md"
      any=1
      BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
      note="was .agent-os/$f.md"
      [[ "$was_symlink" -eq 1 ]] && note="was .agent-os/$f.md, a symlink -- the link itself was moved, not its target"
      BACKED_UP_LIST+=("$backup_dir/$f.md ($note)")
    fi
  done

  for f in CLAUDE.md AGENTS.md; do
    src="$TARGET_ABS/$f"
    if [[ -f "$src" || -L "$src" ]]; then
      was_symlink=0
      [[ -L "$src" ]] && was_symlink=1
      ensure_reset_backup_dir "$backup_dir"
      backup_dir="$RESET_BACKUP_DIR_FINAL"
      mv "$src" "$backup_dir/$f"
      any=1
      BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
      note="was $f"
      [[ "$was_symlink" -eq 1 ]] && note="was $f, a symlink -- the link itself was moved, not its target"
      BACKED_UP_LIST+=("$backup_dir/$f ($note)")
    fi
  done

  if [[ "$any" -eq 1 ]]; then
    BACKUP_DIR="$backup_dir"
    info "reset-adapter: backed up existing protected file(s) to $backup_dir"
  else
    info "reset-adapter: no existing protected files found, nothing to back up"
  fi
}

if [[ "$RESET_ADAPTER" -eq 1 ]]; then
  reset_adapter
fi

# ---- 1. Core project-adapter .agent-os/ files (protected state) ------
copy_dir_contents "$AGENT_OS_ROOT/project-adapter/.agent-os" "$TARGET_ABS/.agent-os" 1
apply_project_name_to_fresh_adapter_state_files

# ---- 1b. Global principle files (OS-owned, always vendored) ----------
copy_file "$AGENT_OS_ROOT/GLOBAL_AGENTS.md" "$TARGET_ABS/.agent-os/GLOBAL_AGENTS.md"

# ---- 2. Claude wiring ---------------------------------------------------
if [[ "$FOR" == "claude" || "$FOR" == "both" ]]; then
  copy_file "$AGENT_OS_ROOT/project-adapter/CLAUDE.md" "$TARGET_ABS/CLAUDE.md" 1
  [[ "$LAST_ACTION" == "installed" ]] && apply_project_name "$TARGET_ABS/CLAUDE.md"

  copy_file "$AGENT_OS_ROOT/GLOBAL_CLAUDE.md" "$TARGET_ABS/.agent-os/GLOBAL_CLAUDE.md"

  copy_dir_contents "$AGENT_OS_ROOT/claude/skills" "$TARGET_ABS/.claude/skills"
  copy_flat_glob "$AGENT_OS_ROOT/claude/agents" "$TARGET_ABS/.claude/agents" "*.md"

  vendor_canonical_skills
fi

# ---- 3. Codex wiring ----------------------------------------------------
if [[ "$FOR" == "codex" || "$FOR" == "both" ]]; then
  copy_file "$AGENT_OS_ROOT/project-adapter/AGENTS.md" "$TARGET_ABS/AGENTS.md" 1
  [[ "$LAST_ACTION" == "installed" ]] && apply_project_name "$TARGET_ABS/AGENTS.md"

  copy_dir_contents "$AGENT_OS_ROOT/codex/skills" "$TARGET_ABS/.agents/skills"
  copy_flat_glob "$AGENT_OS_ROOT/codex/agents" "$TARGET_ABS/.codex/agents" "*.toml"

  vendor_canonical_skills
fi

# ---- Summary --------------------------------------------------------
echo
echo "===== bootstrap-project summary ====="
echo "Target:   $TARGET_ABS"
echo "For:      $FOR"
echo "Installed: $INSTALLED_COUNT file(s)"
for f in "${INSTALLED_LIST[@]:-}"; do
  [[ -n "$f" ]] && echo "  + $f"
done
echo "Skipped:   $SKIPPED_COUNT file(s)"
for f in "${SKIPPED_LIST[@]:-}"; do
  [[ -n "$f" ]] && echo "  - $f"
done
echo "Protected: $PROTECTED_COUNT file(s) (project-owned state, preserved despite --force)"
for f in "${PROTECTED_LIST[@]:-}"; do
  [[ -n "$f" ]] && echo "  ! $f"
done
echo "Blocked:   $BLOCKED_COUNT file(s) (refused: symlinked destination or symlinked parent directory)"
for f in "${BLOCKED_LIST[@]:-}"; do
  [[ -n "$f" ]] && echo "  x $f"
done
if [[ "$RESET_ADAPTER" -eq 1 ]]; then
  echo "Backed up: $BACKED_UP_COUNT file(s)$( [[ -n "$BACKUP_DIR" ]] && echo " -> $BACKUP_DIR" )"
  for f in "${BACKED_UP_LIST[@]:-}"; do
    [[ -n "$f" ]] && echo "  ~ $f"
  done
fi
echo
if [[ "$BLOCKED_COUNT" -gt 0 ]]; then
  echo "Next step: review BLOCKED (symlink) lines above; remove the offending symlink(s) manually, then rerun."
elif [[ "$PROTECTED_COUNT" -gt 0 ]]; then
  echo "Next step: review PROTECTED: lines above; run with --reset-adapter (backs up first) if you really want to replace them."
else
  echo "Next step: run the project-bootstrap skill before changing any code."
fi
echo "======================================"

exit 0
