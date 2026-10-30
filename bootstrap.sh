#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--prepare-only] [--with-git-filter-repo]"
  echo "Run inside WSL2 to prepare and apply the shared Groundwork Unix environment."
  echo "--prepare-only clones the engine and prints preview steps without applying it."
  echo "--with-git-filter-repo installs git-filter-repo for your user with pipx, never with root. It is off by default."
  echo "See docs/git-filter-repo.md."
}

install_commit_guard() {
  local script_dir lib
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  lib="${HOME}/.local/lib/groundwork-windows"
  if [[ ! -f "${script_dir}/core/commit-guard/commit-identity-guard.sh" ]]; then
    echo "The core submodule is missing commit-guard/commit-identity-guard.sh. Run git submodule update --init core, then rerun this entry point." >&2
    exit 1
  fi
  command -v python3 >/dev/null 2>&1 || {
    echo "python3 is not available; skipped the commit identity guard." >&2
    return 0
  }
  mkdir -p "$lib"
  cp "${script_dir}/groundwork-commit-guard.py" "${lib}/groundwork-commit-guard.py"
  chmod 755 "${lib}/groundwork-commit-guard.py"
  # A failure here is reported but does not stop setup.
  python3 -B "${lib}/groundwork-commit-guard.py" apply --guard "${script_dir}/core/commit-guard/commit-identity-guard.sh" ||
    echo "The commit identity guard was not fully applied. Fix the message above and rerun this entry point." >&2
}

prepare_only=0
with_git_filter_repo=0
for arg in "$@"; do
  case "$arg" in
    --prepare-only) prepare_only=1 ;;
    --with-git-filter-repo) with_git_filter_repo=1 ;;
    --help | -h) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 64 ;;
  esac
done

[[ $(uname -s) == Linux ]] || { echo "Run this entry point inside WSL2." >&2; exit 1; }
kernel=$(uname -r)
kernel=${kernel,,}
[[ $kernel == *microsoft-standard* || $kernel == *wsl2* ]] || {
  echo "A standard WSL2 kernel is required. Check wsl --list --verbose in PowerShell." >&2
  exit 1
}
if command -v omarchy >/dev/null 2>&1 || [[ -d /usr/share/omarchy ]]; then
  echo "Use the Omarchy environment repo on an Omarchy machine." >&2; exit 1
fi

command -v git >/dev/null 2>&1 || { echo "Install Git with this OS's package manager first." >&2; exit 1; }
if [[ $prepare_only -eq 0 ]] && ! command -v chezmoi >/dev/null 2>&1; then
  echo "Install chezmoi first using https://www.chezmoi.io/install/; then rerun this entry point." >&2
  exit 1
fi

engine_dir=${GROUNDWORK_ENGINE_DIR:-$HOME/code/groundwork-mac}
engine_url=${GROUNDWORK_REPO_URL:-https://github.com/jasondockery/groundwork-mac.git}
if [[ -e $engine_dir ]]; then
  [[ $(git -C "$engine_dir" rev-parse --show-toplevel) == "$engine_dir" ]] || {
    echo "The engine path must be its own Git checkout: $engine_dir" >&2; exit 1;
  }
  [[ $(git -C "$engine_dir" remote get-url origin) == "$engine_url" ]] || {
    echo "The engine origin differs from the selected URL; inspect it before continuing." >&2; exit 1;
  }
  if ! engine_status=$(git -C "$engine_dir" status --porcelain); then
    echo "Cannot inspect the engine's Git status. Repair it before setup." >&2
    exit 1
  fi
  [[ -z $engine_status ]] || {
    echo "The engine has local edits. Preserve and reconcile them before setup." >&2; exit 1;
  }
else
  mkdir -p "$(dirname "$engine_dir")"
  git clone "$engine_url" "$engine_dir"
fi

if [[ $prepare_only -eq 1 ]]; then
  printf 'Prepared engine at %s. No configuration was applied.\n' "$engine_dir"
  printf 'Read docs/migration.md, then initialize, preview, and apply that source explicitly.\n'
  exit 0
fi

# Opt-in only: a default run never installs git-filter-repo. The helper installs per
# user with no root and never runs a history rewrite. See docs/git-filter-repo.md.
if [[ $with_git_filter_repo -eq 1 ]]; then
  bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-git-filter-repo.sh"
fi

# Commit identity guard (docs/commit-identity.md, groundwork-core v0.9.0), inside WSL2 only.
# Opt out with groundwork-commit-guard off.
install_commit_guard
exec chezmoi --source "$engine_dir" init --apply
