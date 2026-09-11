#!/bin/sh
# remote-worktree-runner.sh --- Detached remote Worktree operation worker
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Usage:
#   remote-worktree-runner.sh dispatch PRIVATE_DIR ATTEMPT_TOKEN
#   remote-worktree-runner.sh run      PRIVATE_DIR ATTEMPT_TOKEN
#   remote-worktree-runner.sh created  PRIVATE_DIR ATTEMPT_TOKEN
#   remote-worktree-runner.sh read PRIVATE_DIR ATTEMPT_TOKEN OPERATION_TOKEN STEP_COUNT [DIAGNOSTIC_STEP]
#   remote-worktree-runner.sh release PRIVATE_DIR ATTEMPT_TOKEN OPERATION_TOKEN STEP_COUNT EXPECTED_RECEIPTS_BASE64
#   remote-worktree-runner.sh bootstrap PRIVATE_DIR ATTEMPT_TOKEN ZMX_PROGRAM NAME
#   remote-worktree-runner.sh agent PRIVATE_DIR ATTEMPT_TOKEN GIT_PROGRAM REPOSITORY TARGET BRANCH NAME PROGRAM [ARG...]
#
# See specs/003-remote-worktree-management/contracts/execution.md for
# the wire format this script implements exactly.  A private directory
# holds a manifest (key=value), an immutable plan.sh, and receipts this
# script writes by atomic rename.  Command stdout/stderr are diagnostic
# files only, never parsed as receipts.
#
# dispatch: validates admission, then starts an independent `run` via
#   nohup with closed stdin and redirected output.  It waits up to 30
#   seconds for worker-started, not completion.  It never takes the claim.
# run: re-validates, then atomically claims the attempt (mkdir), records
#   worker-started, sources the trusted plan.sh exactly once, then
#   records the terminal finished receipt with the count of step-N.entered
#   files actually on disk (never plan.sh's own sourcing exit status).
#   plan.sh owns its own control flow (a flat step list or a cci_plan
#   function it defines and invokes itself); the runner never invokes
#   cci_plan itself, since plan.sh already does and calling it twice
#   would repeat a mutation.  A losing duplicate claim exits without
#   touching any receipt.
# created: invoked by Worktrunk's own execute continuation from inside
#   a newly created worktree.  It records the actual directory/common
#   git directory/branch into creation-result.  It requires an existing
#   claim (from `run`) and never takes a claim itself.
# bootstrap: invoked as the plan's one claimed `bootstrap` step, in the
#   exact destination directory.  It requires the existing attempt claim
#   from `run`, a file-secure bootstrap.sh, and a NAME that passes the
#   same shape check as `claude-code-ide-zmx--valid-name-p'.  It reads
#   one bounded, fully validated zmx inventory and refuses a colliding
#   name before ever invoking zmx, so a collision never runs a
#   replacement command and never stops an existing Agent.  It then
#   starts headless `zmx attach NAME /bin/sh bootstrap.sh ATTEMPT' with
#   closed stdin, backgrounded so the new Session's lifetime never
#   depends on this process, and waits -- bounded, without signaling
#   anything on expiry -- for a matching bootstrap-owned receipt.  A
#   zero attach-client exit alone is never treated as success.
# agent: invoked from inside the new Session by the staged bootstrap.sh
#   wrapper, never through cci_step.  It requires the existing attempt
#   claim from `run`, validates the current canonical directory, Git
#   common directory, and branch (TARGET `created` reads back the
#   creation-result receipt; an empty BRANCH matches only a detached
#   HEAD) against the caller's exact expectations, then atomically
#   claims a wrapper entry so a duplicate invocation exits untouched
#   instead of repeating the launch.  Only then does it record
#   bootstrap-owned and run PROGRAM ARG... as literal argv, with no
#   shell and no redirection, so the Agent keeps the Session's terminal.
#   It records the real exit status in agent-exit whether or not any
#   observer is still reading, and it never kills the Agent itself.
#
# Inside a sourced plan.sh, these functions are available: cci_step
# (run one command, recording entry/exit), cci_protect (spend a fresh
# Agent-inventory check to grant one protected step),
# cci_created_directory (read back a validated creation-result),
# cci_step_merge_cleanup (cci_step for a worktrunk cleanup step, with
# worktrunk.default-branch scoped to its own invocation),
# cci_protect_cleanup (grant one merge-cleanup step once its landing
# receipt, live refs, and source cleanliness all check out), and
# cci_record_merge (write the merge-result receipt cci_protect_cleanup
# later trusts).  cci_step returns the real command exit status, so
# `cci_step ... || return "$?"' inside a plan's cci_plan function
# stops remaining steps on failure while preserving partial effects
# already recorded.
#
# Protected-step Agent-inventory admission (execution contract section
# 4): a plan calls `cci_protect STEP ZMX_PROGRAM GIT_PROGRAM REPOSITORY
# WORKTREE BRANCH HEAD [WORKTREE BRANCH HEAD ...]' immediately before
# `cci_step STEP KIND ...' for a protected KIND (backend-merge,
# named-remove, native-move, native-prune, backend-push, native-push).
# revalidates every listed Worktree's exact Git identity, then spends
# one 30-second watchdog on a fresh Agent-inventory read that must
# both match admitted-inventory's name/pid/created/start_dir/cmd set
# exactly -- an unrelated Agent's title or client-attach change never
# blocks, but any added, removed, or changed Agent does -- and resolve
# to no Agent sitting in any listed Worktree, including one that was
# already there in admitted-inventory itself: matching that baseline
# is never treated as admission on its own.  Any unresolved or
# malformed row blocks like a real conflict.  Success grants STEP a
# one-time admission that cci_step spends and clears; it can never be
# reused for another step or call.  Any other kind outside this small
# executable allowlist is rejected before recording entry, so an
# unreviewed kind can neither run for real nor gain a false
# entered/success receipt.  No placeholder approval file or no-op
# guard stands in for either check.

set -u
CCI_COMMAND_UMASK=$(umask) || exit 1
CCI_COMMAND_LC_ALL_SET=${LC_ALL+x}
CCI_COMMAND_LC_ALL=${LC_ALL-}
umask 077
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR CDPATH
LC_ALL=C
export LC_ALL
CCI_UID=$(id -u) || exit 1

CCI_PROTOCOL=cci-worktree-1

# Set by a successful cci_protect and spent by the immediately
# following cci_step for a protected kind; it never persists across
# more than one cci_step call.
CCI_GRANTED_STEP=

cci_usage() {
  echo "usage: $0 {dispatch|run|created|bootstrap|agent|read|release} PRIVATE_DIR ATTEMPT_TOKEN [ACTION_ARGUMENTS]" >&2
  exit 2
}

# Restore caller policy only in a command child, then replace that child.
cci_exec_command() {
  umask "$CCI_COMMAND_UMASK" || exit 1
  if [ "$CCI_COMMAND_LC_ALL_SET" = x ]; then
    LC_ALL=$CCI_COMMAND_LC_ALL
    export LC_ALL
  else
    unset LC_ALL
  fi
  exec "$@"
}

# --- Low-level file security -------------------------------------------

cci_attributes() {
  stat -c '%u:%a' "$1" 2>/dev/null || stat -f '%u:%Lp' "$1"
}

cci_absolute_path() {
  case $1 in
    *[[:cntrl:]]*) return 1 ;;
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

# cci_validate_file_security FILE
# A regular, non-symlink file owned by the current user with owner-only
# permissions.  Shared by plan.sh and every key=value authority file.
cci_validate_file_security() {
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] && [ -r "$file" ] || return 1
  attributes=$(cci_attributes "$file") || return 1
  case $attributes in
    "$CCI_UID":[0-7]00) return 0 ;;
    *) return 1 ;;
  esac
}

# cci_validate_private_dir DIR
# An absolute, non-symlink directory owned by the current user with
# owner-only permissions.
cci_validate_private_dir() {
  dir=$1
  cci_absolute_path "$dir" || return 1
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  [ "$(cci_attributes "$dir")" = "$CCI_UID:700" ]
}

# cci_valid_token TOKEN
# Exactly 32 lowercase hexadecimal characters.
cci_valid_token() {
  t=$1
  case ${#t} in
    32) : ;;
    *) return 1 ;;
  esac
  case $t in
    *[!0-9a-f]*) return 1 ;;
  esac
  return 0
}

# cci_valid_zmx_name NAME
# Mirrors `claude-code-ide-zmx--valid-name-p' exactly: NAME must be
# non-empty, not a single dot, not start with a hyphen, not end with
# an asterisk, and contain no control character.
cci_valid_zmx_name() {
  n=$1
  [ -n "$n" ] && [ "$n" != "." ] || return 1
  case $n in
    -* | *'*' | *[[:cntrl:]]*) return 1 ;;
  esac
  return 0
}

# --- Authority file (key=value) wire format -----------------------------

# cci_validate_authority_file FILE KEY...
# FILE must be file-secure (see above), at most 16 KiB, and contain only
# "key=value" lines (split at the first "=" only) with no control
# characters, no duplicate keys, no unknown keys, and every listed KEY
# present.
cci_validate_authority_file() {
  file=$1
  shift
  cci_validate_file_security "$file" || return 1
  size=$(wc -c <"$file" 2>/dev/null | tr -d ' \t') || return 1
  case $size in '' | *[!0-9]*) return 1 ;; esac
  [ "$size" -le 16384 ] || return 1
  iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1 || return 1
  tr -d '\000-\011\013-\037\177' <"$file" | cmp -s - "$file" || return 1
  awk '/\302[\200-\237]/ {exit 1}' "$file" || return 1
  seen=""
  while IFS= read -r line; do
    case $line in
      *[[:cntrl:]]*) return 1 ;;
    esac
    case $line in
      *=*) : ;;
      *) return 1 ;;
    esac
    key=${line%%=*}
    [ -n "$key" ] || return 1
    match=0
    for k in "$@"; do
      if [ "$k" = "$key" ]; then
        match=1
        break
      fi
    done
    [ "$match" -eq 1 ] || return 1
    case " $seen " in
      *" $key "*) return 1 ;;
    esac
    seen="$seen $key"
  done <"$file"
  [ -z "$line" ] || return 1
  for k in "$@"; do
    case " $seen " in
      *" $k "*) : ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# cci_kv_get FILE KEY
# Print KEY's value from an already-validated FILE, or fail if absent.
cci_kv_get() {
  file=$1
  key=$2
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      "$key="*)
        printf '%s\n' "${line#*=}"
        return 0
        ;;
    esac
  done <"$file"
  return 1
}

# cci_atomic_kv PATH LINE...
# Write LINEs into a same-directory temp file, then rename atomically
# into PATH.  Never derives the temp name from untrusted content.
cci_atomic_kv() {
  path=$1
  shift
  tmp=$(mktemp "$CCI_PRIVATE_DIR/receipt.XXXXXXXXXX") || return 1
  keys=
  for line in "$@"; do
    keys="$keys ${line%%=*}"
    printf '%s\n' "$line" >>"$tmp" || {
      rm -f "$tmp"
      return 1
    }
  done
  cci_validate_authority_file "$tmp" $keys || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$path"
}

# --- Manifest admission --------------------------------------------------

# cci_validate_manifest PRIVATE_DIR ATTEMPT
# On success sets CCI_PRIVATE_DIR, CCI_ATTEMPT, CCI_OPERATION, CCI_KIND,
# CCI_STEPS for the rest of this process.
cci_validate_manifest() {
  private_dir=$1
  attempt=$2
  cci_validate_private_dir "$private_dir" || return 1
  cci_valid_token "$attempt" || return 1
  manifest="$private_dir/manifest"
  cci_validate_authority_file "$manifest" protocol operation attempt kind steps \
    || return 1
  proto=$(cci_kv_get "$manifest" protocol) || return 1
  [ "$proto" = "$CCI_PROTOCOL" ] || return 1
  m_attempt=$(cci_kv_get "$manifest" attempt) || return 1
  cci_valid_token "$m_attempt" || return 1
  [ "$m_attempt" = "$attempt" ] || return 1
  m_operation=$(cci_kv_get "$manifest" operation) || return 1
  cci_valid_token "$m_operation" || return 1
  m_kind=$(cci_kv_get "$manifest" kind) || return 1
  case $m_kind in
    list | open | create | remove | move | merge | push | prune) : ;;
    *) return 1 ;;
  esac
  m_steps=$(cci_kv_get "$manifest" steps) || return 1
  case $m_steps in '' | 0* | *[!0-9]*) return 1 ;; esac
  [ "$m_steps" -ge 1 ] 2>/dev/null || return 1
  CCI_PRIVATE_DIR=$private_dir
  CCI_ATTEMPT=$attempt
  CCI_OPERATION=$m_operation
  CCI_KIND=$m_kind
  CCI_STEPS=$m_steps
  return 0
}

# --- Plan-visible functions ----------------------------------------------

# cci_step NUMBER KIND CWD PROGRAM [ARG...]
# Record entry, run PROGRAM ARG... in CWD with its stdout/stderr saved as
# separate diagnostic files, record exit, and return the real exit
# status so a plan's `cci_step ... || return "$?"` halts on failure.
cci_step() {
  [ $# -ge 4 ] || return 1
  step=$1
  shift
  case $step in '' | 0* | *[!0-9]*) return 1 ;; esac
  [ "$step" -le "$CCI_STEPS" ] 2>/dev/null || return 1
  [ ! -e "$CCI_PRIVATE_DIR/step-$step.entered" ] \
    && [ ! -L "$CCI_PRIVATE_DIR/step-$step.entered" ] || return 1
  if [ "$step" -gt 1 ]; then
    previous=$((step - 1))
    cci_validate_authority_file "$CCI_PRIVATE_DIR/step-$previous.exit" \
      attempt step status || return 1
    [ "$(cci_kv_get "$CCI_PRIVATE_DIR/step-$previous.exit" attempt)" = "$CCI_ATTEMPT" ] \
      && [ "$(cci_kv_get "$CCI_PRIVATE_DIR/step-$previous.exit" status)" = 0 ] \
      || return 1
  fi
  kind=$1
  cwd=$2
  cci_absolute_path "$cwd" || return 1
  shift 2
  case $kind in
    backend-setup | backend-create | bootstrap | record-result) : ;;
    backend-merge | named-remove | native-move | native-prune | backend-push | native-push)
      [ "${CCI_GRANTED_STEP:-}" = "$step" ] || return 1
      CCI_GRANTED_STEP=
      ;;
    *) return 1 ;;
  esac
  [ $# -ge 1 ] || return 1
  case $1 in '' | -* | *[[:cntrl:]]*) return 1 ;; esac
  cci_atomic_kv "$CCI_PRIVATE_DIR/step-$step.entered" \
    "attempt=$CCI_ATTEMPT" "step=$step" "state=entered" \
    || return 1
  (
    cd "$cwd" 2>/dev/null && cci_exec_command "$@"
  ) >"$CCI_PRIVATE_DIR/step-$step.stdout" 2>"$CCI_PRIVATE_DIR/step-$step.stderr"
  status=$?
  cci_atomic_kv "$CCI_PRIVATE_DIR/step-$step.exit" \
    "attempt=$CCI_ATTEMPT" "step=$step" "status=$status" || return 1
  return "$status"
}

# cci_step_merge_cleanup STEP KIND CWD TARGET PROGRAM ARG...
# Run a named-remove step exactly like cci_step, but with
# worktrunk.default-branch overridden to TARGET for PROGRAM's
# process only.  Existing inherited GIT_CONFIG_COUNT/KEY_n/VALUE_n
# entries are preserved -- the override is appended after them --
# and every GIT_CONFIG_* variable this function touches is restored
# to its exact prior state once PROGRAM exits, so no later step in
# the same run observes it.  Main renders this helper only for a
# worktrunk cleanup step's `wt remove --foreground' invocation, so
# KIND must be named-remove and ARG must open with that literal pair.
cci_step_merge_cleanup() {
  [ $# -ge 7 ] || return 1
  step=$1
  kind=$2
  cwd=$3
  target=$4
  shift 4
  [ "$kind" = "named-remove" ] || return 1
  [ "$2" = "remove" ] && [ "$3" = "--foreground" ] || return 1
  case $target in '' | -* | *[[:cntrl:]]*) return 1 ;; esac

  saved_count_set=${GIT_CONFIG_COUNT+x}
  saved_count=${GIT_CONFIG_COUNT-}
  if [ -z "$saved_count_set" ]; then
    n=0
  else
    case $saved_count in
      '' | *[!0-9]*) return 1 ;;
      0) n=0 ;;
      0*) return 1 ;;
      *) n=$saved_count ;;
    esac
  fi

  GIT_CONFIG_COUNT=$((n + 1))
  eval "GIT_CONFIG_KEY_$n=worktrunk.default-branch; export GIT_CONFIG_KEY_$n"
  eval "GIT_CONFIG_VALUE_$n=\"\$target\"; export GIT_CONFIG_VALUE_$n"
  export GIT_CONFIG_COUNT

  cci_step "$step" "$kind" "$cwd" "$@"
  status=$?

  unset "GIT_CONFIG_KEY_$n" "GIT_CONFIG_VALUE_$n"
  if [ -n "$saved_count_set" ]; then
    GIT_CONFIG_COUNT=$saved_count
    export GIT_CONFIG_COUNT
  else
    unset GIT_CONFIG_COUNT
  fi
  return "$status"
}
# cci_created_directory
# Validate creation-result against the plan-supplied CCI_EXPECTED_REPOSITORY
# and CCI_EXPECTED_BRANCH (both required) and this attempt, then print
# only the recorded directory.  Fails closed (nonzero, no stdout) on any
# missing expectation, missing/invalid receipt, or identity mismatch, so
# a hook-selected foreign repository or branch can never reach bootstrap.
cci_created_directory() {
  [ -n "${CCI_EXPECTED_REPOSITORY:-}" ] || return 1
  [ -n "${CCI_EXPECTED_BRANCH:-}" ] || return 1
  file="$CCI_PRIVATE_DIR/creation-result"
  cci_validate_authority_file "$file" attempt directory repository branch \
    || return 1
  a=$(cci_kv_get "$file" attempt) || return 1
  [ "$a" = "$CCI_ATTEMPT" ] || return 1
  r=$(cci_kv_get "$file" repository) || return 1
  [ "$r" = "$CCI_EXPECTED_REPOSITORY" ] || return 1
  b=$(cci_kv_get "$file" branch) || return 1
  [ "$b" = "$CCI_EXPECTED_BRANCH" ] || return 1
  d=$(cci_kv_get "$file" directory) || return 1
  cci_absolute_path "$d" || return 1
  printf '%s\n' "$d"
  return 0
}

# cci_git_common_dir GIT_PROGRAM WORKTREE
# Print WORKTREE's canonical common Git directory using GIT_PROGRAM,
# resolving a relative `--git-common-dir' answer (the main worktree
# reports a bare ".git") against WORKTREE first.  Always invoked
# through command substitution, so it never changes the caller's
# working directory.
cci_git_common_dir() {
  git_program=$1
  worktree=$2
  raw_common=$(cd "$worktree" 2>/dev/null \
    && "$git_program" rev-parse --git-common-dir 2>/dev/null) || return 1
  case $raw_common in
    /*) common_path=$raw_common ;;
    *) common_path="$worktree/$raw_common" ;;
  esac
  (cd "$common_path" 2>/dev/null && pwd -P) || return 1
}

# cci_git_worktree_root GIT_PROGRAM DIRECTORY
# Print the canonical Git working-tree root that DIRECTORY sits
# inside, using GIT_PROGRAM.  Fails when DIRECTORY does not exist or
# is not inside any Git working tree.
cci_git_worktree_root() {
  git_program=$1
  directory=$2
  raw_top=$(cd "$directory" 2>/dev/null \
    && "$git_program" rev-parse --show-toplevel 2>/dev/null) || return 1
  (cd "$raw_top" 2>/dev/null && pwd -P) || return 1
}

# cci_git_branch_matches GIT_PROGRAM WORKTREE BRANCH
# BRANCH matches WORKTREE's exact current short branch, or BRANCH is
# empty and WORKTREE's HEAD is detached (no symbolic ref at all).
cci_git_branch_matches() {
  git_program=$1
  worktree=$2
  branch=$3
  if current_branch=$(cd "$worktree" 2>/dev/null \
      && "$git_program" symbolic-ref --quiet --short HEAD 2>/dev/null); then
    [ -n "$branch" ] && [ "$current_branch" = "$branch" ]
  else
    branch_status=$?
    [ "$branch_status" -eq 1 ] && [ -z "$branch" ]
  fi
}

# cci_normalize_inventory FILE
# Print one "name<TAB>pid<TAB>created<TAB>start_dir<TAB>cmd" line per
# zmx-list row in FILE, dropping clients and title -- the only fields
# an attach or a title change may legitimately move between two reads.
# FILE must contain an empty-list diagnostic or tab-separated key=value
# rows with all five identity fields. Accept start_dir or the zmx 0.8
# cwd=file://HOST/PATH form, as the Emacs inventory parser does.
cci_normalize_inventory() {
  iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1 || return 1
  normalized=$(awk '
    function unhex(value, result, at, digits, byte, hex) {
      hex = "0123456789abcdef"
      result = ""
      while ((at = index(value, "%")) != 0) {
        digits = tolower(substr(value, at + 1, 2))
        if (digits !~ /^[0-9a-f][0-9a-f]$/) exit 1
        byte = (index(hex, substr(digits, 1, 1)) - 1) * 16 \
             + index(hex, substr(digits, 2, 1)) - 1
        if (byte < 32 || byte == 127) exit 1
        result = result substr(value, 1, at - 1) sprintf("%c", byte)
        value = substr(value, at + 3)
      }
      return result value
    }
    BEGIN { FS = "\t"; rows = 0; empty = 0 }
    $0 ~ /^no sessions found( in [^[:cntrl:]]+)?$/ {
      if (rows || empty) exit 1
      empty = 1
      next
    }
    {
      if (empty || length($0) == 0) exit 1
      sub(/^[ ]+/, "", $0)
      for (key in count) delete count[key]
      name = ""; pid = ""; created = ""; dir = ""; cmd = ""
      for (c = 1; c <= NF; c++) {
        eq = index($c, "=")
        if (eq == 0) exit 1
        key = substr($c, 1, eq - 1)
        val = substr($c, eq + 1)
        if (++count[key] != 1 || val ~ /[[:cntrl:]]/ || val ~ /\302[\200-\237]/) exit 1
        if (key == "name") name = val
        else if (key == "pid") pid = val
        else if (key == "created") created = val
        else if (key == "start_dir" || key == "cwd") {
          if (dir != "") exit 1
          if (key == "cwd") {
            if (val !~ /^file:\/\/[^\/]*\//) exit 1
            sub(/^file:\/\/[^\/]*/, "", val)
            val = unhex(val)
            if (val ~ /[[:cntrl:]]/ || val ~ /\302[\200-\237]/) exit 1
          }
          dir = val
        }
        else if (key == "cmd") cmd = val
        else if (key == "clients") { if (val !~ /^[0-9]+$/) exit 1 }
        else if (key != "title") exit 1
      }
      if (name == "" || pid !~ /^[1-9][0-9]*$/ || created == "" ||
          dir !~ /^\// || cmd == "" || ++names[name] != 1) exit 1
      rows++
      printf "%s\t%s\t%s\t%s\t%s\n", name, pid, created, dir, cmd
    }
    END { if (!rows && !empty) exit 1 }
  ' "$1") || return 1
  printf '%s\n' "$normalized" | iconv -f UTF-8 -t UTF-8
}

# Bound one owned read process.  Its start signature prevents a late
# watchdog from signaling a different process after PID reuse.
cci_watchdog_run() {
  budget=$1
  shift
  ( ulimit -f 128; "$@" </dev/null >/dev/null 2>&1 ) &
  worker=$!
  identity=$(ps -o lstart= -o args= -p "$worker" 2>/dev/null)
  (
    sleep "$budget"
    current=$(ps -o lstart= -o args= -p "$worker" 2>/dev/null)
    [ -n "$identity" ] && [ "$identity" = "$current" ] \
      && kill -KILL "$worker" 2>/dev/null
  ) &
  watcher=$!
  wait "$worker"
  status=$?
  kill -TERM "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return "$status"
}

# All protected-target and inventory reads share one watchdog budget.

# cci_protect_inventory_check ZMX_PROGRAM GIT_PROGRAM
# Shared tail of cci_protect_body and cci_protect_cleanup_body: the
# caller has already written every protected Worktree's canonical
# path, one per line (possibly zero lines), to
# "$CCI_PRIVATE_DIR/protect-targets".  Compares a fresh zmx-list read
# to admitted-inventory exactly, then confirms no listed Agent's
# start_dir resolves inside a protected Worktree.
cci_protect_inventory_check() {
  zmx_program=$1
  git_program=$2
  cci_validate_file_security "$CCI_PRIVATE_DIR/admitted-inventory" || return 1
  admitted_size=$(wc -c <"$CCI_PRIVATE_DIR/admitted-inventory" | tr -d ' \t')
  case $admitted_size in '' | *[!0-9]*) return 1 ;; esac
  [ "$admitted_size" -gt 0 ] && [ "$admitted_size" -le 65536 ] || return 1
  fresh="$CCI_PRIVATE_DIR/protect-fresh"
  fresh_norm="$CCI_PRIVATE_DIR/protect-fresh.norm"
  admitted_norm="$CCI_PRIVATE_DIR/protect-admitted.norm"
  rm -f "$fresh" "$fresh_norm" "$admitted_norm"

  "$zmx_program" list >"$fresh" 2>&1 || { rm -f "$fresh"; return 1; }
  size=$(wc -c <"$fresh" 2>/dev/null | tr -d ' \t')
  case $size in '' | *[!0-9]*) rm -f "$fresh"; return 1 ;; esac
  [ "$size" -gt 0 ] && [ "$size" -le 65536 ] || { rm -f "$fresh"; return 1; }

  if ! cci_normalize_inventory "$fresh" >"$fresh_norm" \
      || ! cci_normalize_inventory "$CCI_PRIVATE_DIR/admitted-inventory" >"$admitted_norm"
  then
    rm -f "$fresh" "$fresh_norm" "$admitted_norm"
    return 1
  fi
  sort -o "$fresh_norm" "$fresh_norm"
  sort -o "$admitted_norm" "$admitted_norm"
  if ! cmp -s "$fresh_norm" "$admitted_norm"; then
    rm -f "$fresh" "$fresh_norm" "$admitted_norm"
    return 1
  fi

  tab=$(printf '\t')
  conflict=0
  while IFS="$tab" read -r name pid created start_dir cmd; do
    [ -n "$name" ] || continue
    root=$(cci_git_worktree_root "$git_program" "$start_dir") || { conflict=1; break; }
    while IFS= read -r protected_target; do
      case "$root/" in
        "${protected_target%/}/"*) conflict=1; break ;;
      esac
    done <"$CCI_PRIVATE_DIR/protect-targets"
    [ "$conflict" -eq 0 ] || break
  done <"$fresh_norm"

  rm -f "$fresh" "$fresh_norm" "$admitted_norm"
  [ "$conflict" -eq 0 ]
}

cci_protect_body() {
  unset ZMX_SESSION ZMX_SESSION_PREFIX
  zmx_program=$1
  git_program=$2
  repository=$3
  shift 3
  cci_absolute_path "$repository" && [ -d "$repository" ] || return 1
  repository=$(cd "$repository" 2>/dev/null && pwd -P) || return 1
  targets="$CCI_PRIVATE_DIR/protect-targets"
  rm -f "$targets"
  : >"$targets" || return 1
  while [ $# -ge 3 ]; do
    worktree=$1
    branch=$2
    head=$3
    shift 3
    cci_absolute_path "$worktree" || return 1
    case $branch in *[[:cntrl:]]*) return 1 ;; esac
    case $head in '' | *[!0-9a-f]*) return 1 ;; esac
    case ${#head} in 40 | 64) ;; *) return 1 ;; esac
    common=$(cci_git_common_dir "$git_program" "$worktree") || return 1
    [ "$common" = "$repository" ] || return 1
    canonical=$(cci_git_worktree_root "$git_program" "$worktree") || return 1
    physical=$(cd "$worktree" 2>/dev/null && pwd -P) || return 1
    [ "$canonical" = "$physical" ] || return 1
    cci_git_branch_matches "$git_program" "$worktree" "$branch" || return 1
    current_head=$(cd "$worktree" 2>/dev/null \
      && "$git_program" rev-parse HEAD 2>/dev/null) || return 1
    [ "$current_head" = "$head" ] || return 1
    printf '%s\n' "$canonical" >>"$targets" || return 1
  done
  cci_protect_inventory_check "$zmx_program" "$git_program"
}

# cci_protect_cleanup_body ZMX_PROGRAM GIT_PROGRAM REPOSITORY WORKTREE
#                          BRANCH LANDING_STEP SOURCE_REF TARGET_REF
# Admits a post-merge removal instead of a static pre-merge HEAD
# check: LANDING_STEP must have exited 0 for this attempt, its
# recorded merge-result must name exactly SOURCE_REF and TARGET_REF,
# both refs must still resolve to the oids merge-result recorded (a
# moved source or target refuses cleanup rather than deleting past
# it), and WORKTREE must have no uncommitted changes.
cci_protect_cleanup_body() {
  zmx_program=$1
  git_program=$2
  repository=$3
  worktree=$4
  branch=$5
  landing_step=$6
  source_ref=$7
  target_ref=$8

  case $landing_step in '' | 0* | *[!0-9]*) return 1 ;; esac
  [ "$landing_step" -le "$CCI_STEPS" ] 2>/dev/null || return 1
  case $source_ref in refs/*) ;; *) return 1 ;; esac
  case $target_ref in refs/*) ;; *) return 1 ;; esac
  case $source_ref in *[[:cntrl:]]*) return 1 ;; esac
  case $target_ref in *[[:cntrl:]]*) return 1 ;; esac

  cci_validate_authority_file "$CCI_PRIVATE_DIR/step-$landing_step.exit" \
    attempt step status || return 1
  [ "$(cci_kv_get "$CCI_PRIVATE_DIR/step-$landing_step.exit" attempt)" = "$CCI_ATTEMPT" ] \
    && [ "$(cci_kv_get "$CCI_PRIVATE_DIR/step-$landing_step.exit" step)" = "$landing_step" ] \
    && [ "$(cci_kv_get "$CCI_PRIVATE_DIR/step-$landing_step.exit" status)" = 0 ] \
    || return 1

  merge_result="$CCI_PRIVATE_DIR/merge-result"
  cci_validate_authority_file "$merge_result" \
    attempt step source-ref source-oid target-ref target-oid || return 1
  [ "$(cci_kv_get "$merge_result" attempt)" = "$CCI_ATTEMPT" ] \
    && [ "$(cci_kv_get "$merge_result" step)" = "$landing_step" ] \
    && [ "$(cci_kv_get "$merge_result" source-ref)" = "$source_ref" ] \
    && [ "$(cci_kv_get "$merge_result" target-ref)" = "$target_ref" ] \
    || return 1
  recorded_source_oid=$(cci_kv_get "$merge_result" source-oid) || return 1
  recorded_target_oid=$(cci_kv_get "$merge_result" target-oid) || return 1

  cci_absolute_path "$repository" && [ -d "$repository" ] || return 1
  repository=$(cd "$repository" 2>/dev/null && pwd -P) || return 1
  current_source_oid=$("$git_program" --git-dir="$repository" rev-parse --verify -q \
    "$source_ref" 2>/dev/null) || return 1
  current_target_oid=$("$git_program" --git-dir="$repository" rev-parse --verify -q \
    "$target_ref" 2>/dev/null) || return 1
  [ "$current_source_oid" = "$recorded_source_oid" ] || return 1
  [ "$current_target_oid" = "$recorded_target_oid" ] || return 1

  cci_absolute_path "$worktree" || return 1
  common=$(cci_git_common_dir "$git_program" "$worktree") || return 1
  [ "$common" = "$repository" ] || return 1
  canonical=$(cci_git_worktree_root "$git_program" "$worktree") || return 1
  physical=$(cd "$worktree" 2>/dev/null && pwd -P) || return 1
  [ "$canonical" = "$physical" ] || return 1
  cci_git_branch_matches "$git_program" "$worktree" "$branch" || return 1
  clean=$(cd "$worktree" 2>/dev/null \
    && "$git_program" status --porcelain 2>/dev/null) || return 1
  [ -z "$clean" ] || return 1

  targets="$CCI_PRIVATE_DIR/protect-targets"
  rm -f "$targets"
  printf '%s\n' "$canonical" >"$targets" || return 1
  cci_protect_inventory_check "$zmx_program" "$git_program"
}

# cci_protect STEP ZMX_PROGRAM GIT_PROGRAM REPOSITORY
#             [WORKTREE BRANCH HEAD ...]
# Grant STEP once after its complete bounded read check succeeds.
# Zero triples is valid: native-prune's candidates are already
# nonexistent directories with nothing live to name, but the fresh
# zmx-list comparison against admitted-inventory still always runs.
cci_protect() {
  [ $# -ge 4 ] || return 1
  step=$1
  shift
  case $step in '' | 0* | *[!0-9]*) return 1 ;; esac
  [ "$step" -le "$CCI_STEPS" ] 2>/dev/null || return 1
  [ ! -e "$CCI_PRIVATE_DIR/step-$step.entered" ] \
    && [ ! -L "$CCI_PRIVATE_DIR/step-$step.entered" ] || return 1

  zmx_program=$1
  git_program=$2
  repository=$3
  shift 3
  case $zmx_program in /*) ;; *) return 1 ;; esac
  case $git_program in /*) ;; *) return 1 ;; esac
  [ $(($# % 3)) -eq 0 ] || return 1
  cci_watchdog_run 30 cci_protect_body "$zmx_program" "$git_program" "$repository" "$@"
  status=$?
  rm -f "$CCI_PRIVATE_DIR/protect-targets" "$CCI_PRIVATE_DIR/protect-fresh" \
    "$CCI_PRIVATE_DIR/protect-fresh.norm" "$CCI_PRIVATE_DIR/protect-admitted.norm"
  if [ "$status" -ne 0 ]; then
    echo "Protected step $step refused. Refresh Agent and Worktree identities." >&2
    return 1
  fi

  CCI_GRANTED_STEP=$step
  return 0
}

# cci_protect_cleanup STEP ZMX_PROGRAM GIT_PROGRAM REPOSITORY WORKTREE
#                      BRANCH LANDING_STEP SOURCE_REF TARGET_REF
# Grant STEP once cleanup of WORKTREE/BRANCH is confirmed safe.  See
# cci_protect_cleanup_body for the checks this spends its one
# 30-second watchdog budget on.
cci_protect_cleanup() {
  [ $# -eq 9 ] || return 1
  step=$1
  zmx_program=$2
  git_program=$3
  repository=$4
  worktree=$5
  branch=$6
  landing_step=$7
  source_ref=$8
  target_ref=$9
  case $step in '' | 0* | *[!0-9]*) return 1 ;; esac
  [ "$step" -le "$CCI_STEPS" ] 2>/dev/null || return 1
  [ ! -e "$CCI_PRIVATE_DIR/step-$step.entered" ] \
    && [ ! -L "$CCI_PRIVATE_DIR/step-$step.entered" ] || return 1
  case $landing_step in '' | 0* | *[!0-9]*) return 1 ;; esac
  [ "$landing_step" -lt "$step" ] 2>/dev/null || return 1
  case $zmx_program in /*) ;; *) return 1 ;; esac
  case $git_program in /*) ;; *) return 1 ;; esac
  cci_watchdog_run 30 cci_protect_cleanup_body "$zmx_program" "$git_program" \
    "$repository" "$worktree" "$branch" "$landing_step" "$source_ref" "$target_ref"
  status=$?
  rm -f "$CCI_PRIVATE_DIR/protect-targets" "$CCI_PRIVATE_DIR/protect-fresh" \
    "$CCI_PRIVATE_DIR/protect-fresh.norm" "$CCI_PRIVATE_DIR/protect-admitted.norm"
  if [ "$status" -ne 0 ]; then
    echo "Protected cleanup step $step refused. Refresh Agent and Worktree identities." >&2
    return 1
  fi

  CCI_GRANTED_STEP=$step
  return 0
}

# cci_record_merge STEP GIT_PROGRAM REPOSITORY SOURCE_REF TARGET_REF
# Resolve SOURCE_REF and TARGET_REF against REPOSITORY right now and
# record them, with their oids, as the merge-result authority for
# STEP.  Independently confirms STEP's own exit receipt already
# shows success for this attempt before recording anything, since
# cci_protect_cleanup later trusts merge-result to admit a separate,
# protected removal of the source Worktree.
cci_record_merge() {
  [ $# -eq 5 ] || return 1
  step=$1
  git_program=$2
  repository=$3
  source_ref=$4
  target_ref=$5
  case $step in '' | 0* | *[!0-9]*) return 1 ;; esac
  [ "$step" -le "$CCI_STEPS" ] 2>/dev/null || return 1
  cci_validate_authority_file "$CCI_PRIVATE_DIR/step-$step.exit" \
    attempt step status || return 1
  [ "$(cci_kv_get "$CCI_PRIVATE_DIR/step-$step.exit" attempt)" = "$CCI_ATTEMPT" ] \
    && [ "$(cci_kv_get "$CCI_PRIVATE_DIR/step-$step.exit" step)" = "$step" ] \
    && [ "$(cci_kv_get "$CCI_PRIVATE_DIR/step-$step.exit" status)" = 0 ] \
    || return 1
  case $git_program in /*) ;; *) return 1 ;; esac
  cci_absolute_path "$repository" && [ -d "$repository" ] || return 1
  repository=$(cd "$repository" 2>/dev/null && pwd -P) || return 1
  case $source_ref in refs/*) ;; *) return 1 ;; esac
  case $target_ref in refs/*) ;; *) return 1 ;; esac
  case $source_ref in *[[:cntrl:]]*) return 1 ;; esac
  case $target_ref in *[[:cntrl:]]*) return 1 ;; esac
  source_oid=$("$git_program" --git-dir="$repository" rev-parse --verify -q \
    "$source_ref" 2>/dev/null) || return 1
  target_oid=$("$git_program" --git-dir="$repository" rev-parse --verify -q \
    "$target_ref" 2>/dev/null) || return 1
  file="$CCI_PRIVATE_DIR/merge-result"
  [ ! -e "$file" ] && [ ! -L "$file" ] || return 1
  cci_atomic_kv "$file" \
    "attempt=$CCI_ATTEMPT" "step=$step" \
    "source-ref=$source_ref" "source-oid=$source_oid" \
    "target-ref=$target_ref" "target-oid=$target_oid"
}

# --- worker-started signature --------------------------------------------

cci_start_signature() {
  signature_pid=${1:-$$}
  sig=$(ps -o lstart= -p "$signature_pid" 2>/dev/null) || return 1
  command_identity=$(ps -o args= -p "$signature_pid" 2>/dev/null) || return 1
  sig=$(printf '%s' "$sig" | tr -s ' \t' ' ')
  sig=${sig# }
  [ -n "$sig" ] && [ -n "$command_identity" ] || return 1
  printf '%s|%s' "$sig" "$command_identity"
}

# --- CLI actions -----------------------------------------------------------

cci_await_worker_started() {
  file="$CCI_PRIVATE_DIR/worker-started"
  while [ ! -e "$file" ] && [ ! -L "$file" ]; do sleep 0.01; done
  cci_validate_authority_file "$file" attempt pid start-signature || return 1
  [ "$(cci_kv_get "$file" attempt)" = "$CCI_ATTEMPT" ] || return 1
  case $(cci_kv_get "$file" pid) in '' | 0 | *[!0-9]*) return 1 ;; esac
  [ -n "$(cci_kv_get "$file" start-signature)" ]
}

cci_do_dispatch() {
  [ $# -eq 2 ] || cci_usage
  private_dir=$1
  attempt=$2
  cci_validate_manifest "$private_dir" "$attempt" || exit 1
  cci_validate_file_security "$private_dir/plan.sh" || exit 1
  cci_exec_command nohup /bin/sh "$0" run "$private_dir" "$attempt" \
    </dev/null >>"$private_dir/worker.log" 2>&1 &
  # Acknowledgment proves admission, not merely a successful fork.
  # The watchdog owns only this read, never the detached mutation.
  cci_watchdog_run 30 cci_await_worker_started
  exit $?
}

cci_do_run() {
  [ $# -eq 2 ] || cci_usage
  private_dir=$1
  attempt=$2
  cci_validate_manifest "$private_dir" "$attempt" || exit 1
  if ! mkdir "$CCI_PRIVATE_DIR/claimed" 2>/dev/null; then
    # A duplicate attempt already owns this claim.  Never re-execute.
    exit 0
  fi
  start_signature=$(cci_start_signature) || exit 1
  cci_atomic_kv "$CCI_PRIVATE_DIR/worker-started" \
    "attempt=$CCI_ATTEMPT" "pid=$$" \
    "start-signature=$start_signature" \
    || exit 1
  plan="$CCI_PRIVATE_DIR/plan.sh"
  cci_validate_file_security "$plan" || exit 1
  # shellcheck disable=SC1090
  . "$plan"
  # plan.sh defines and invokes its own control flow (cci_plan or a
  # flat step list); do not call cci_plan here too, or it would repeat
  # the mutation it already ran while this file was sourced.
  entered=0
  for f in "$CCI_PRIVATE_DIR"/step-*.entered; do
    [ -e "$f" ] || continue
    entered=$((entered + 1))
  done
  cci_atomic_kv "$CCI_PRIVATE_DIR/finished" \
    "attempt=$CCI_ATTEMPT" "entered=$entered" "state=finished"
  exit 0
}

cci_do_created() {
  [ $# -eq 2 ] || cci_usage
  private_dir=$1
  attempt=$2
  cci_validate_manifest "$private_dir" "$attempt" || exit 1
  # Never takes a claim: the ancestor `run` invocation already owns one.
  [ -d "$CCI_PRIVATE_DIR/claimed" ] || exit 1
  new_dir=$(pwd -P) || exit 1
  raw_common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 1
  case $raw_common in
    /*) common_path=$raw_common ;;
    *) common_path="$new_dir/$raw_common" ;;
  esac
  common_dir=$(cd "$common_path" 2>/dev/null && pwd -P) || exit 1
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || exit 1
  cci_atomic_kv "$CCI_PRIVATE_DIR/creation-result" \
    "attempt=$CCI_ATTEMPT" "directory=$new_dir" \
    "repository=$common_dir" "branch=$branch"
  exit $?
}

# --- Agent bootstrap and launch ------------------------------------------

# cci_bootstrap_admission_body ZMX_PROGRAM NAME
# Read one bounded, fully validated `zmx list' snapshot and fail unless
# every row is well-formed and none of them already uses NAME.  Talks to
# its caller only through its exit status.
cci_bootstrap_admission_body() {
  zmx_program=$1
  name=$2
  fresh="$CCI_PRIVATE_DIR/bootstrap-fresh"
  fresh_norm="$CCI_PRIVATE_DIR/bootstrap-fresh.norm"
  rm -f "$fresh" "$fresh_norm"
  "$zmx_program" list >"$fresh" 2>&1 || { rm -f "$fresh"; return 1; }
  size=$(wc -c <"$fresh" 2>/dev/null | tr -d ' \t')
  case $size in '' | *[!0-9]*) rm -f "$fresh"; return 1 ;; esac
  [ "$size" -gt 0 ] && [ "$size" -le 65536 ] || { rm -f "$fresh"; return 1; }
  if ! cci_normalize_inventory "$fresh" >"$fresh_norm"; then
    rm -f "$fresh" "$fresh_norm"
    return 1
  fi
  collision=0
  cut -f1 "$fresh_norm" | grep -qxF -- "$name" && collision=1
  rm -f "$fresh" "$fresh_norm"
  [ "$collision" -eq 0 ]
}

# cci_await_bootstrap_owned NAME
# Poll, without signaling any process, for a bootstrap-owned receipt that
# names this attempt and NAME.  Give up after a fixed budget; expiry is a
# plain failure, never a kill of the wrapper or the Agent.
cci_await_bootstrap_owned() {
  name=$1
  file="$CCI_PRIVATE_DIR/bootstrap-owned"
  waited=0
  while [ "$waited" -lt 30 ]; do
    if cci_validate_authority_file "$file" attempt name directory token; then
      [ "$(cci_kv_get "$file" attempt)" = "$CCI_ATTEMPT" ] \
        && [ "$(cci_kv_get "$file" name)" = "$name" ] \
        && [ "$(cci_kv_get "$file" token)" = "$CCI_ATTEMPT" ]
      return $?
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

cci_do_bootstrap() {
  unset ZMX_SESSION ZMX_SESSION_PREFIX
  [ $# -eq 4 ] || cci_usage
  private_dir=$1
  attempt=$2
  zmx_program=$3
  name=$4
  cci_validate_manifest "$private_dir" "$attempt" || exit 1
  # Never takes a claim: the ancestor `run` invocation already owns one.
  [ -d "$CCI_PRIVATE_DIR/claimed" ] || exit 1
  cci_validate_file_security "$CCI_PRIVATE_DIR/bootstrap.sh" || exit 1
  case $zmx_program in /*) ;; *) exit 1 ;; esac
  cci_valid_zmx_name "$name" || exit 1
  cci_watchdog_run 30 cci_bootstrap_admission_body "$zmx_program" "$name"
  status=$?
  rm -f "$CCI_PRIVATE_DIR/bootstrap-fresh" "$CCI_PRIVATE_DIR/bootstrap-fresh.norm"
  if [ "$status" -ne 0 ]; then
    echo "Name $name is unresolved, malformed, or already in use; no attach sent." >&2
    exit 1
  fi
  cci_exec_command nohup "$zmx_program" attach "$name" /bin/sh "$CCI_PRIVATE_DIR/bootstrap.sh" "$CCI_ATTEMPT" \
    </dev/null >/dev/null 2>&1 &
  if cci_await_bootstrap_owned "$name"; then
    exit 0
  fi
  echo "No ownership receipt for $name; an attach-client exit alone is not launch success." >&2
  exit 1
}

cci_do_agent() {
  [ $# -ge 8 ] || cci_usage
  private_dir=$1
  attempt=$2
  git_program=$3
  repository=$4
  target=$5
  branch=$6
  name=$7
  program=$8
  shift 8
  cci_validate_manifest "$private_dir" "$attempt" || exit 1
  # Never takes a claim: the ancestor `run` invocation already owns one.
  [ -d "$CCI_PRIVATE_DIR/claimed" ] || exit 1
  case $git_program in /*) ;; *) exit 1 ;; esac
  case $branch in *[[:cntrl:]]*) exit 1 ;; esac
  case $program in '' | -* | *[[:cntrl:]]*) exit 1 ;; esac
  cci_absolute_path "$repository" && [ -d "$repository" ] || exit 1
  repository=$(cd "$repository" 2>/dev/null && pwd -P) || exit 1
  if [ "$target" = created ]; then
    CCI_EXPECTED_REPOSITORY=$repository
    CCI_EXPECTED_BRANCH=$branch
    target_directory=$(cci_created_directory) || exit 1
  else
    cci_absolute_path "$target" && [ -d "$target" ] || exit 1
    target_directory=$(cd "$target" 2>/dev/null && pwd -P) || exit 1
  fi
  [ "$(pwd -P)" = "$target_directory" ] || exit 1
  common=$(cci_git_common_dir "$git_program" "$target_directory") || exit 1
  [ "$common" = "$repository" ] || exit 1
  cci_git_branch_matches "$git_program" "$target_directory" "$branch" || exit 1
  if ! mkdir "$CCI_PRIVATE_DIR/wrapper-claimed" 2>/dev/null; then
    # A duplicate wrapper invocation already claimed this attempt.  Never
    # run PROGRAM twice or republish bootstrap-owned/agent-exit.
    exit 0
  fi
  cci_atomic_kv "$CCI_PRIVATE_DIR/bootstrap-owned" \
    "attempt=$CCI_ATTEMPT" "name=$name" "directory=$target_directory" \
    "token=$CCI_ATTEMPT" || exit 1
  (cci_exec_command "$program" "$@")
  status=$?
  cci_atomic_kv "$CCI_PRIVATE_DIR/agent-exit" \
    "attempt=$CCI_ATTEMPT" "name=$name" "status=$status"
  exit "$status"
}

# Read only fixed authority names.  Base64 frames file contents separately
# from transport headers and diagnostic output.  No read action sources a plan.
cci_read_receipt() {
  receipt_name=$1
  shift
  receipt_path="$CCI_PRIVATE_DIR/$receipt_name"
  if [ ! -e "$receipt_path" ] && [ ! -L "$receipt_path" ]; then
    return 0
  fi
  cci_validate_authority_file "$receipt_path" "$@" || return 1
  encoded=$(base64 <"$receipt_path") || return 1
  printf 'file=%s\t' "$receipt_name"
  printf '%s' "$encoded" | tr -d '\n'
  printf '\n'
}

cci_read_receipts() {
  cci_read_receipt manifest protocol operation attempt kind steps || return 1
  cci_read_receipt worker-started attempt pid start-signature || return 1
  number=1
  while [ "$number" -le "$CCI_STEPS" ]; do
    cci_read_receipt "step-$number.entered" attempt step state || return 1
    cci_read_receipt "step-$number.exit" attempt step status || return 1
    number=$((number + 1))
  done
  cci_read_receipt creation-result attempt directory repository branch || return 1
  cci_read_receipt merge-result attempt step source-ref source-oid target-ref target-oid || return 1
  cci_read_receipt bootstrap-owned attempt name directory token || return 1
  cci_read_receipt agent-exit attempt name status || return 1
  cci_read_receipt finished attempt entered state || return 1
}

cci_read_diagnostic() {
  diagnostic_name=$1
  diagnostic_path="$CCI_PRIVATE_DIR/$diagnostic_name"
  if [ ! -e "$diagnostic_path" ] && [ ! -L "$diagnostic_path" ]; then
    return 0
  fi
  cci_validate_file_security "$diagnostic_path" || return 1
  printf 'diagnostic=%s\t' "$diagnostic_name"
  dd if="$diagnostic_path" bs=65536 count=1 2>/dev/null | base64 | tr -d '\n'
  printf '\n'
}

cci_do_read() {
  [ $# -eq 4 ] || [ $# -eq 5 ] || cci_usage
  cci_validate_manifest "$1" "$2" || exit 1
  [ "$CCI_OPERATION" = "$3" ] && [ "$CCI_STEPS" = "$4" ] || exit 1
  diagnostic_step=${5:-}
  if [ -n "$diagnostic_step" ]; then
    case $diagnostic_step in 0* | *[!0-9]*) exit 1 ;; esac
    [ "$diagnostic_step" -le "$CCI_STEPS" ] 2>/dev/null || exit 1
  fi
  # Keep the liveness sample inside the receipt consistency window.
  first=$(cci_read_receipts) || exit 1
  if [ -z "$diagnostic_step" ] && [ -f "$CCI_PRIVATE_DIR/finished" ]; then
    cci_validate_authority_file "$CCI_PRIVATE_DIR/finished" attempt entered state || exit 1
    diagnostic_step=$(cci_kv_get "$CCI_PRIVATE_DIR/finished" entered) || exit 1
    case $diagnostic_step in 0) diagnostic_step= ;; '' | 0* | *[!0-9]*) exit 1 ;; esac
    [ -z "$diagnostic_step" ] || [ "$diagnostic_step" -le "$CCI_STEPS" ] 2>/dev/null || exit 1
  fi
  live=unknown
  if [ -f "$CCI_PRIVATE_DIR/worker-started" ]; then
    worker_pid=$(cci_kv_get "$CCI_PRIVATE_DIR/worker-started" pid) || exit 1
    case $worker_pid in '' | 0* | *[!0-9]*) exit 1 ;; esac
    expected_signature=$(cci_kv_get "$CCI_PRIVATE_DIR/worker-started" start-signature) || exit 1
    current_signature=$(cci_start_signature "$worker_pid") || current_signature=
    live=0
    if [ -n "$current_signature" ] && [ "$current_signature" = "$expected_signature" ]; then
      case $current_signature in
        *"|/bin/sh $CCI_PRIVATE_DIR/runner.sh run $CCI_PRIVATE_DIR $CCI_ATTEMPT") live=1 ;;
        *) live=unknown ;;
      esac
    fi
  fi
  second=$(cci_read_receipts) || exit 1
  generation=changed
  [ "$first" = "$second" ] && generation=stable
  printf 'cci-receipts-1\ngeneration=%s\nworker-live=%s\n%s\n' \
    "$generation" "$live" "$first"
  cci_read_diagnostic worker.log || exit 1
  if [ -n "$diagnostic_step" ]; then
    cci_read_diagnostic "step-$diagnostic_step.stdout" || exit 1
    cci_read_diagnostic "step-$diagnostic_step.stderr" || exit 1
  fi
  exit 0
}

# Release only the exact resource whose complete terminal evidence Emacs retained.
# A fresh process listing also excludes a wrapper that published its last receipt
# but has not yet exited.  Never source resource code or signal any process.
cci_do_release() {
  [ $# -eq 5 ] || cci_usage
  cci_validate_manifest "$1" "$2" || exit 1
  [ "$CCI_OPERATION" = "$3" ] && [ "$CCI_STEPS" = "$4" ] || exit 1
  [ "$(cd "$CCI_PRIVATE_DIR" && pwd -P)" = "$CCI_PRIVATE_DIR" ] || exit 1
  expected_receipts=$(printf '%s' "$5" | base64 -d) || exit 1
  current_receipts=$(cci_read_receipts) || exit 1
  [ -n "$expected_receipts" ] && [ "$current_receipts" = "$expected_receipts" ] || exit 1
  cci_validate_authority_file "$CCI_PRIVATE_DIR/finished" attempt entered state || exit 1
  [ "$(cci_kv_get "$CCI_PRIVATE_DIR/finished" attempt)" = "$CCI_ATTEMPT" ] || exit 1
  [ "$(cci_kv_get "$CCI_PRIVATE_DIR/finished" state)" = finished ] || exit 1
  [ "$(cci_kv_get "$CCI_PRIVATE_DIR/finished" entered)" = "$CCI_STEPS" ] || exit 1
  release_step=1
  while [ "$release_step" -le "$CCI_STEPS" ]; do
    cci_validate_authority_file "$CCI_PRIVATE_DIR/step-$release_step.exit" attempt step status || exit 1
    [ "$(cci_kv_get "$CCI_PRIVATE_DIR/step-$release_step.exit" status)" = 0 ] || exit 1
    release_step=$((release_step + 1))
  done
  if [ -e "$CCI_PRIVATE_DIR/bootstrap-owned" ] || [ -L "$CCI_PRIVATE_DIR/bootstrap-owned" ]; then
    cci_validate_authority_file "$CCI_PRIVATE_DIR/agent-exit" attempt name status || exit 1
  fi
  owned_commands=$(ps -ww -u "$CCI_UID" -o args=) || exit 1
  printf '%s\n' "$owned_commands" |
    while IFS= read -r owned_command; do
      case $owned_command in
        "/bin/sh $CCI_PRIVATE_DIR/runner.sh run $CCI_PRIVATE_DIR $CCI_ATTEMPT" | \
        "/bin/sh $CCI_PRIVATE_DIR/bootstrap.sh $CCI_ATTEMPT") exit 1 ;;
      esac
    done || exit 1
  [ "$(cci_read_receipts)" = "$expected_receipts" ] || exit 1
  cci_validate_private_dir "$CCI_PRIVATE_DIR" || exit 1
  rm -rf -- "$CCI_PRIVATE_DIR" || exit 1
  printf 'released\n'
}

[ $# -ge 1 ] || cci_usage
action=$1
shift
case $action in
  dispatch) cci_do_dispatch "$@" ;;
  run) cci_do_run "$@" ;;
  created) cci_do_created "$@" ;;
  bootstrap) cci_do_bootstrap "$@" ;;
  agent) cci_do_agent "$@" ;;
  read) cci_do_read "$@" ;;
  release) cci_do_release "$@" ;;
  *) cci_usage ;;
esac
