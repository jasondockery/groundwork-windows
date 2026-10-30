#!/usr/bin/env bash
# Opt-in, per-user git-filter-repo for history purges. Run by bootstrap.sh only
# after --with-git-filter-repo. The contract is groundwork-core
# docs/history-purge.md: install into the user's home with no root, and prove it
# with `git filter-repo -h` listing --sensitive-data-removal. This script never
# runs a history rewrite, a force-push, or a tag change.
set -euo pipefail

# Per-user bin first, then the system dirs appended last. The tests set
# GROUNDWORK_SYSTEM_BIN_DIRS (empty is allowed) so a host pipx stays out of reach.
system_dirs="${GROUNDWORK_SYSTEM_BIN_DIRS-/usr/local/bin:/usr/bin:/bin}"
export PATH="$HOME/.local/bin:$PATH${system_dirs:+:$system_dirs}"

has_proof() {
  git filter-repo -h 2>&1 | grep -q -- '--sensitive-data-removal'
}

# Idempotent: a copy that already shows the flag is left alone.
if has_proof; then
  echo "git-filter-repo is installed (proof: git filter-repo -h lists --sensitive-data-removal)."
  exit 0
fi

if ! command -v pipx >/dev/null 2>&1; then
  echo "pipx is not installed, so git-filter-repo was not installed. Install pipx for your user (your distribution's pipx package or 'python3 -m pip install --user pipx'), then rerun with --with-git-filter-repo." >&2
  exit 0
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "GNU timeout is required to bound the install, so git-filter-repo was not installed. Install coreutils, then rerun with --with-git-filter-repo." >&2
  exit 0
fi

if pipx list --short 2>/dev/null | grep -q '^git-filter-repo '; then
  timeout --kill-after=5s 300 pipx upgrade git-filter-repo </dev/null || true
else
  timeout --kill-after=5s 300 pipx install git-filter-repo </dev/null || true
fi

if has_proof; then
  echo "git-filter-repo installed for this user (proof: git filter-repo -h lists --sensitive-data-removal)."
else
  echo "git-filter-repo is not usable: 'git filter-repo -h' does not list --sensitive-data-removal. Rerun with --with-git-filter-repo to retry." >&2
fi
exit 0
