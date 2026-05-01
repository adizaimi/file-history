#!/usr/bin/env bash
# file-history.sh
#
# Lightweight, file-local change history that can later be imported into Git.
#
# This script records incremental changes to a single file as a series of
# mbox-style patch emails, similar to `git format-patch --stdout`. Each
# invocation:
#
#   - compares the target file against the last saved snapshot
#   - generates a unified diff (with a/FILE and b/FILE labels)
#   - wraps that diff in an email-like header (From, Date, Subject, etc.)
#   - appends it to a single .mbox file next to the target
#   - updates the snapshot for the next run
#
# No Git repository is needed while you iterate; you just run this script on
# your standalone file whenever you want to "commit" a change with a message.
#
# Files created next to the target FILE:
#   .FILE.base          - last committed snapshot of FILE
#   .FILE.patches.mbox  - mbox containing one patch email per invocation
#
# Usage:
#   file-history.sh FILE [message...]
#
# Examples:
#   ./file-history.sh script.py "initial version"
#   # edit script.py...
#   ./file-history.sh script.py "add foo() helper"
#   # edit script.py...
#   ./file-history.sh script.py "fix edge case in foo()"
#
# If [message...] is omitted, the script uses "no message".
#
# Importing the history into Git later:
#
#   1. Create or cd into a Git repo:
#        git init my-repo
#        cd my-repo
#
#   2. Copy only the mbox (do NOT pre-copy the target file):
#        cp /path/to/.script.py.patches.mbox .
#
#   3. Apply the recorded history as real Git commits:
#        git am .script.py.patches.mbox
#
# Each recorded change becomes its own commit (with the message you supplied),
# preserving the per-"commit" boundaries exactly like a `git format-patch`
# series.
#
# Requirements:
#   - POSIX shell utilities: diff, cp, date, mktemp
#   - A SHA-1 utility: sha1sum (Linux) or shasum (macOS)
#   - git (only needed when reconstructing .base from .patches.mbox)

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  file-history.sh commit|ci FILE [message...]
  file-history.sh diff FILE

Commands:
  commit, ci   Record a patch email into .FILE.patches.mbox and update .FILE.base
  diff         Show working diff between .FILE.base and FILE (like git diff)

Notes:
  - If .FILE.base is missing but .FILE.patches.mbox exists, base is reconstructed
    by applying the mbox in a temporary git repo and copying the resulting file.
  - Running without a command prints this usage.
EOF
  exit 1
}

sha1_hex() {
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 1 | awk '{print $1}'
    return
  fi
  return 1
}

ensure_base_from_mbox() {
  local file="$1"
  local base="$2"
  local mbox="$3"
  local name="$4"

  # If base already exists, nothing to do.
  if [ -f "$base" ]; then
    return 0
  fi

  # No base and no mbox means nothing to reconstruct.
  if [ ! -f "$mbox" ]; then
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "Error: '$base' is missing and git is required to reconstruct from '$mbox'" >&2
    exit 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"

  # Best-effort cleanup of temp directory.
  cleanup_tmpdir() {
    rm -rf "$tmpdir"
  }
  trap cleanup_tmpdir RETURN

  git -C "$tmpdir" init >/dev/null 2>&1
  git -C "$tmpdir" config user.name "${GIT_AUTHOR_NAME:-Local User}" >/dev/null 2>&1
  git -C "$tmpdir" config user.email "${GIT_AUTHOR_EMAIL:-local@example.com}" >/dev/null 2>&1
  git -C "$tmpdir" am "$mbox" >/dev/null 2>&1

  if [ -f "$tmpdir/$name" ]; then
    cp "$tmpdir/$name" "$base"
    echo "Reconstructed base snapshot '$base' from '$mbox'"
  else
    echo "Error: could not reconstruct '$name' from '$mbox'" >&2
    exit 1
  fi
}

# Running with no args now prints usage by design.
[ $# -ge 1 ] || usage

cmd="$1"
shift

case "$cmd" in
  commit|ci|diff)
    ;;
  *)
    usage
    ;;
esac

[ $# -ge 1 ] || usage

file="$1"
shift || true

if [ "$cmd" = "diff" ] && [ $# -ne 0 ]; then
  usage
fi

if [ ! -f "$file" ]; then
  echo "Error: file '$file' does not exist" >&2
  exit 1
fi

dir="$(cd "$(dirname "$file")" && pwd)"
name="$(basename "$file")"

base="$dir/.${name}.base"              # last committed snapshot
mbox="$dir/.${name}.patches.mbox"      # mbox-style series

if [ "$cmd" = "commit" ] || [ "$cmd" = "ci" ]; then
  msg="$*"
  [ -z "$msg" ] && msg="no message"
fi

# If base is missing, try to reconstruct from existing mbox history.
ensure_base_from_mbox "$file" "$base" "$mbox" "$name"

if [ "$cmd" = "diff" ]; then
  if [ ! -f "$base" ]; then
    # No historical base; show add-from-empty view.
    diff -u --label "/dev/null" --label "b/$name" -- /dev/null "$file" || true
    exit 0
  fi

  diff -u --label "a/$name" --label "b/$name" -- "$base" "$file" || true
  exit 0
fi

# Author info (use git env vars if set)
author_name="${GIT_AUTHOR_NAME:-Local User}"
author_email="${GIT_AUTHOR_EMAIL:-local@example.com}"

# Timestamps
date_rfc="$(date -R)"                     # for Date: header
date_from="$(date '+%a %b %d %T %Y')"    # for "From " line

# Synthetic commit id (40-hex, like a SHA-1)
commit_id="$(
  { printf '%s\n' "$date_rfc"; printf '%s\n' "$file"; printf '%s\n' "$msg"; } \
    | sha1_hex 2>/dev/null || true
)"

# Fallback if sha1sum is missing
if [ -z "$commit_id" ]; then
  commit_id="$(printf '%040d' "$(date +%s)")"
fi

# Generate unified diff with proper labels.
# First run uses /dev/null so replay creates the file cleanly via git am.
tmp_old=""
if [ ! -f "$base" ]; then
  diff_output="$(
    diff -u --label "/dev/null" --label "b/$name" -- /dev/null "$file" || true
  )"
else
  old="$base"
  diff_output="$(
    diff -u --label "a/$name" --label "b/$name" -- "$old" "$file" || true
  )"
fi

# If there is no diff, don't write an empty patch email
if [ -z "$diff_output" ]; then
  echo "No changes; nothing recorded."
  [ -n "$tmp_old" ] && rm -f "$tmp_old"
  exit 0
fi

{
  # mbox "From " line
  echo "From $commit_id $date_from"
  echo "From: $author_name <$author_email>"
  echo "Date: $date_rfc"
  echo "Subject: [PATCH] $msg"
  echo "MIME-Version: 1.0"
  echo "Content-Type: text/plain; charset=UTF-8"
  echo "Content-Transfer-Encoding: 8bit"
  echo
  echo "$diff_output"
  echo
} >> "$mbox"

# Update base snapshot for next run
cp "$file" "$base"

[ -n "$tmp_old" ] && rm -f "$tmp_old"

echo "Recorded patch for '$file' into '$mbox'"
