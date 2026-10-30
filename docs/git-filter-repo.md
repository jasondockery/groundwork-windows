# git-filter-repo for history purges (opt-in)

When a credential or private reference has to leave a repository's history, the procedure is the shared runbook, not this page: [groundwork-core `docs/history-purge.md`](https://github.com/jasondockery/groundwork-core/blob/v0.9.0/docs/history-purge.md). Read it before any rewrite. This page records only the WSL2 install: what this repo installs, when, and how you remove it.

`git-filter-repo` is not a default. A normal `bash bootstrap.sh` does not install it. Setup never runs a history rewrite, a force-push, or a tag change.

## Turn it on

```bash
bash bootstrap.sh --with-git-filter-repo
```

Run this inside WSL2. `git-filter-repo` belongs there, where Groundwork's Unix engine runs and your repositories are used, not on the Windows host. The engine in `groundwork-mac` installs it only on macOS, so this entry point owns the WSL2 install. It is one-shot and is not saved. The helper `install-git-filter-repo.sh` runs `pipx install git-filter-repo` under a 300-second timeout. It installs into your home directory, with no root and no `sudo`. It needs `pipx` already present; if it is not, the helper says so and installs nothing. A distribution's `pipx` package needs a one-time `sudo` by the machine owner, and `python3 -m pip install --user pipx` fails on Debian 12+ and Ubuntu 24.04+ (externally-managed-environment), so do not rely on it. The root-free route is mise: `mise use -g pipx:git-filter-repo` installs the tool directly when mise and `uv` are present, and the proof check below still applies. Running it again changes nothing once the proof below passes. The runbook's install table lists other per-user options.

## Prove it

```bash
git filter-repo -h | grep -- --sensitive-data-removal
```

The runbook requires that flag. A distro package can be older than 2.47 and lack it, so the help text decides, not the package name. The helper runs the same check and reports a failure without failing setup.

## Update it

Run `pipx upgrade git-filter-repo`. Rerunning `bash bootstrap.sh --with-git-filter-repo` also upgrades an installed copy that lacks the proof flag. If you installed with mise, use `mise upgrade pipx:git-filter-repo`.

## Remove it

Run `pipx uninstall git-filter-repo` (or `mise unuse -g pipx:git-filter-repo` then `mise uninstall pipx:git-filter-repo` for the mise route). Optionally remove `pipx` itself if nothing else of yours uses it. Nothing is saved between runs, so omitting the flag later is enough to stay off.
