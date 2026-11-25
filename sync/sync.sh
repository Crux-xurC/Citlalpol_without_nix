#!/usr/bin/env bash
# sync/sync.sh -- regenerate this repository from Citlalpol (the upstream).
#
#   sync/sync.sh <path to the Citlalpol repository> [<rev>]     (rev: main)
#
# Citlalpol is written for Nix: `nix develop` gives Elixir/OTP, and citl runs as
# `elixir main.exs` (lib/citlalpol/*.ex required in order). This repository is the
# same tree made a Mix project, so that a release (Erlang's runtime included) can
# be built and run without Nix. Changes flow one way, Citlalpol -> here: never edit
# an upstream file here, change Citlalpol and sync.
#
# What it does, from `git archive <rev>` of Citlalpol (only committed files):
#   - drops flake.nix and flake.lock
#   - does not take the files in sync/replaced.txt (replaced by this repository's
#     own work); keeps upstream's version of each under sync/upstream/ and, when
#     one changed, prints the difference -- carry it into the replacement by hand
#   - README.md -> README.citlalpol.md (README.md here is this repository's own)
#   - .gitignore: upstream's, then sync/gitignore.extra
#   - removes the files the previous sync wrote (.upstream-files) that upstream no
#     longer has; refuses when an upstream file would overwrite one of this
#     repository's own
#   - records the upstream commit in sync/UPSTREAM and its tree in sync/UPSTREAM_TREE
#
# It refuses to run on a dirty working tree (commit or stash first), so that
# `git diff` after it shows exactly what the sync changed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream="${1:?usage: sync/sync.sh <path to Citlalpol> [<rev>]}"
rev="${2:-main}"
upstream="$(cd "$upstream" && pwd)"

cd "$here"
if [ -n "$(git status --porcelain)" ]; then
  echo "sync: the working tree is not clean; commit or stash first" >&2
  exit 1
fi

commit="$(git -C "$upstream" rev-parse --verify "$rev^{commit}")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$upstream" archive "$commit" | tar -x -C "$tmp"

# --- drop what is Nix's; set aside what this repository replaces ----------------
rm -f "$tmp/flake.nix" "$tmp/flake.lock"
replaced="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$here/sync/replaced.txt" | awk '{print $1}')"
mkdir -p "$tmp/.replaced"
for p in $replaced; do
  if [ ! -f "$tmp/$p" ]; then
    echo "sync: upstream no longer has $p (sync/replaced.txt) -- see whether its replacement is still needed" >&2
    continue
  fi
  mkdir -p "$tmp/.replaced/$(dirname "$p")"
  mv "$tmp/$p" "$tmp/.replaced/$p"
done
mv "$tmp/.replaced" "$here/.replaced.new"

# --- README: upstream's is kept as README.citlalpol.md -----------------------------
mv "$tmp/README.md" "$tmp/README.citlalpol.md"

# --- .gitignore ----------------------------------------------------------------
{ cat "$tmp/.gitignore"; echo; cat "$here/sync/gitignore.extra"; } > "$tmp/.gitignore.new"
mv "$tmp/.gitignore.new" "$tmp/.gitignore"

# --- the list of upstream files, and collisions with this repository's own -----
( cd "$tmp" && find . -type f -o -type l | sed 's|^\./||' | LC_ALL=C sort ) > "$here/.upstream-files.new"
touch "$here/.upstream-files"
while IFS= read -r p; do
  if [ -e "$here/$p" ] && ! grep -qxF "$p" "$here/.upstream-files"; then
    if git -C "$here" ls-files --error-unmatch "$p" >/dev/null 2>&1; then
      echo "sync: upstream now has $p, which is this repository's own" >&2
      rm -rf "$here/.upstream-files.new" "$here/.replaced.new"
      exit 1
    fi
  fi
done < "$here/.upstream-files.new"

# --- remove what the previous sync wrote, then write ---------------------------
while IFS= read -r p; do
  [ -n "$p" ] && rm -f "$here/$p"
done < "$here/.upstream-files"
find "$here" -mindepth 1 -type d -empty -not -path "$here/.git*" -not -path "$here/_build*" -delete
cp -a "$tmp/." "$here/"
mv "$here/.upstream-files.new" "$here/.upstream-files"

# --- the replaced files: upstream's versions, and what changed -------------------
for p in $replaced; do
  [ -f "$here/.replaced.new/$p" ] || continue
  if [ -f "$here/sync/upstream/$p" ] && ! cmp -s "$here/sync/upstream/$p" "$here/.replaced.new/$p"; then
    echo
    echo "sync: $p changed upstream -- carry this into its replacement (sync/replaced.txt):"
    diff -u "$here/sync/upstream/$p" "$here/.replaced.new/$p" || true
  fi
done
rm -rf "$here/sync/upstream"
mv "$here/.replaced.new" "$here/sync/upstream"
echo "$commit" > "$here/sync/UPSTREAM"
git -C "$upstream" rev-parse "$commit^{tree}" > "$here/sync/UPSTREAM_TREE"

echo
echo "sync: Citlalpol $commit"
echo "sync: review with git status / git diff, then bin/release and bin/test"
