# groundwork-windows

The Windows/WSL2 entry point for the Groundwork environment: T3 Code Nightly, Herdr, and Omarchy-style terminal habits where they fit. Run `bootstrap.sh` inside WSL2, not PowerShell, CMD, Git Bash, WSL1, or an Omarchy installation. The Windows host keeps its own desktop, input, and permissions.

The shared Unix provisioning implementation currently lives in `groundwork-mac`. This repo owns the Windows/WSL boundary, migration instructions, and host-side guidance; it does not duplicate that engine. Its visible engine checkout remains the chezmoi source and update owner. Shared operational guidance lives in [groundwork-core](https://github.com/jasondockery/groundwork-core); the original Groundwork curriculum stays available and unchanged.

## Setup

In PowerShell, inspect `wsl --list --verbose` and use a WSL2 distribution. Inside its Linux terminal, clone this repo over HTTPS into a new directory, install Git and chezmoi through their supported Linux sources, inspect `bootstrap.sh`, then run `bash bootstrap.sh`. Existing Groundwork users should follow [migration](docs/migration.md) to preview the new source before applying it.

`GROUNDWORK_ENGINE_DIR` selects the engine checkout, defaulting to `~/code/groundwork-mac` inside WSL. `GROUNDWORK_REPO_URL` selects its Git URL, defaulting to `https://github.com/jasondockery/groundwork-mac.git`. Public HTTPS access needs no GitHub login. If your existing engine uses SSH, set this variable to that exact origin URL before running the wrapper; its remote is preserved. Existing engine checkouts must match that URL and be clean. The engine's platform checks remain authoritative; this wrapper does not promise support for every custom WSL kernel or native Windows provisioning.

T3 Code Nightly and Herdr run in WSL2 through that engine. If you want a native Windows T3 Code UI too, use the official [Nightly releases](https://github.com/pingdotgg/t3code/releases) and select your WSL distribution in Settings → Connections. Authenticate provider CLIs inside the environment that runs them. A host app or GitHub login does not authenticate providers inside WSL.

## Keyboard and remote access

Use Omarchy's terminal chords inside tmux and Herdr: `Ctrl+Space`, Alt+Enter splits, Ctrl+Alt+arrow pane focus, and aligned tab/session actions. If Windows Terminal or another host app intercepts a chord, clear that host binding in its supported settings and verify delivery in the multiplexer. Do not remap the whole Windows desktop or assume Linux can configure host input.

Install Tailscale on the Windows host for normal access to that machine; see [Tailscale setup](docs/tailscale.md). WSL is a separate environment, so host connectivity alone does not publish its SSH server. Choose Both in `groundwork-configure` when you want tmux lessons alongside Herdr.

## Updates

Review and pull this entry point with `git pull --ff-only`. The engine owns applied Unix configuration and `update-all`; Windows apps keep their supported Windows updater. Do not run two competing Tailscale or agent-server installations without deliberately choosing their ownership.

## License

[MIT](LICENSE), matching the Groundwork family.
