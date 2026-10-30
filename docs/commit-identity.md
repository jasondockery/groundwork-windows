# Commit identity guard

The contract is groundwork-core `docs/commit-identity.md` (v0.9.0): no `Co-authored-by` trailer, and no author or committer that matches your local denylist. `bash bootstrap.sh`, run inside WSL2 and never on the Windows host, installs the reference guard from the `core` pin through `groundwork-commit-guard.py`, before it hands over to the shared engine. It does not run under `--prepare-only`.

## What it does

- **Scope is your own repositories.** Hooks live in `~/.config/groundwork/git-hooks`. `commit-identity-guard.sh` there is a symlink to the pinned `core/commit-guard/commit-identity-guard.sh`, so the pin is the only copy. `core.hooksPath` is never set globally. It lives in `~/.config/groundwork/commit-guard.gitconfig`, and `~/.config/git/config` includes that file through four `includeIf "hasconfig:remote.*.url:..."` entries: `https://github.com/<owner>/**`, `git@github.com:<owner>/**`, `ssh://git@github.com/<owner>/**` and `*:<owner>/**` (any SSH host alias). Each owner letter matches in either case, and the trailing `/` keeps a look-alike such as `<owner>2` out. Work repositories and hook tools such as pre-commit are untouched.
- **Git 2.36 or newer.** Older git gets one warning and no activation.
- **An existing `core.hooksPath` is respected.** If one is set anywhere, nothing is written and one line says so. Chain `commit-msg` and `pre-push` from your hooks directory to use the guard. Only an exact global path written by an earlier Groundwork install is removed.
- **Per-repository hooks keep running.** Every documented hook name forwards to the repository's own `.git/hooks/<name>` after the guard. `pre-push` input is buffered and given to both.
- **Claude Code attribution.** `attribution.commit` and `attribution.pr` become `""` in `~/.claude/settings.json` (`CLAUDE_CONFIG_DIR` honored) only where the key is absent. Other keys, the file mode and a symlink are kept, a numbered `settings.json.bak.N` is written first, and invalid JSON is left untouched.
- **Denylist.** An empty `~/.config/groundwork/commit-denylist` is created when missing. This repository never supplies a value; names stay in that local file.

## Opt out and check

- `groundwork-commit-guard off` creates `~/.config/groundwork/commit-guard-off`. The hooks check it at run time and setup installs nothing while it exists. `groundwork-commit-guard on` removes it.
- `GROUNDWORK_COMMIT_GUARD=off git ...` bypasses one command. A blocked commit prints both ways out.
- `groundwork-commit-guard doctor` reports the scope, any global `core.hooksPath`, the opt-out, owned repositories that bypass the guard, and the guard's own `doctor` output. The command is copied to `~/.local/bin` and never replaces a file that is not Groundwork's.
- A rerun that finds everything in place prints nothing and changes nothing. A failure warns and does not stop setup.

## Known gaps

- Remote URLs with userinfo (`https://user@github.com/...`) are not matched.
- A push straight to an owned URL from a repository with no owned remote is not guarded.
- A commit made before an owned remote exists is caught at `pre-push` once one is added.
- An owned repository with its own local `core.hooksPath` (husky, lefthook) bypasses the guard. `doctor` lists those under `~/code` (`GROUNDWORK_CODE_DIR` overrides).
- If the pinned guard symlink does not resolve, a hook prints one warning instead of skipping silently.
- Cursor attribution is a UI setting that `doctor` cannot read.
- The shared engine may install the same guard through chezmoi once it adopts groundwork-core v0.9.0. Both write the same hook directory, so the one that runs last owns the dispatcher text and the guard symlink target.
