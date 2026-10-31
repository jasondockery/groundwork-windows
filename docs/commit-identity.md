# Commit identity guard

The contract is groundwork-core `docs/commit-identity.md`, at the version the engine pins (v0.9.0 or later; this repository's own `core` pin is not the one that applies): no `Co-authored-by` trailer, and no author or committer that matches your local denylist.

## Ownership

The shared engine, `groundwork-mac`, installs the guard on every OS through `home/run_after_24-commit-identity-guard.sh.tmpl`. `bash bootstrap.sh` here hands over to that chezmoi apply, so this repository installs nothing of its own and carries no second copy. A second installer would fight the engine over the dispatcher and the guard symlink.

What the engine does, for reference:

- Hooks live in `~/.config/groundwork/git-hooks`, with the guard as a symlink to the pinned core script. `core.hooksPath` is never global. It is set in `~/.config/groundwork/commit-guard.gitconfig` and included from `~/.config/git/config` through `includeIf "hasconfig:remote.*.url:..."` entries for your own GitHub remotes only. Git older than 2.36 gets one warning and no activation, and an existing `core.hooksPath` is respected.
- Claude Code `attribution.commit` and `attribution.pr` are set to empty only where unset, with a numbered backup. The denylist is created empty and never filled by Groundwork.
- Opt out with `~/.config/groundwork/commit-guard-off` or `GROUNDWORK_COMMIT_GUARD=off` for one command. Check with `groundwork-doctor --commit-identity`.

Change the install behaviour, scope patterns and known gaps in the engine, not here. This repository only needs an engine that includes it, so run `update-all` or `groundwork-update` after the engine adopts a new core pin.
