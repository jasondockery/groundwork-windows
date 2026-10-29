# groundwork-windows

The Windows/WSL2 entry point for the Groundwork environment: T3 Code Nightly, Herdr, and Omarchy-style terminal habits where they fit. Run `bootstrap.sh` inside WSL2, not PowerShell, CMD, Git Bash, WSL1, or an Omarchy installation. The Windows host keeps its own desktop, input, and permissions.

The shared Unix provisioning implementation currently lives in `groundwork-mac`. This repo owns the Windows/WSL boundary, migration instructions, and host-side guidance; it does not duplicate that engine. Its visible engine checkout remains the chezmoi source and update owner. Shared operational guidance lives in [groundwork-core](https://github.com/jasondockery/groundwork-core); the original Groundwork curriculum stays available and unchanged.

## Setup

In PowerShell, inspect `wsl --list --verbose` and use a WSL2 distribution. Inside its Linux terminal, clone this repo over HTTPS into a new directory, install Git and chezmoi through their supported Linux sources, inspect `bootstrap.sh`, then run `bash bootstrap.sh`. Existing Groundwork users should follow [migration](docs/migration.md) to preview the new source before applying it.

`GROUNDWORK_ENGINE_DIR` selects the engine checkout, defaulting to `~/code/groundwork-mac` inside WSL. `GROUNDWORK_REPO_URL` selects its Git URL, defaulting to `https://github.com/jasondockery/groundwork-mac.git`. Public HTTPS access needs no GitHub login. If your existing engine uses SSH, set this variable to that exact origin URL before running the wrapper; its remote is preserved. Existing engine checkouts must match that URL and be clean. The engine's platform checks remain authoritative; this wrapper does not promise support for every custom WSL kernel or native Windows provisioning.

T3 Code Nightly and Herdr run in WSL2 through that engine. If you want a native Windows T3 Code UI too, use the official [Nightly releases](https://github.com/pingdotgg/t3code/releases) and select your WSL distribution in Settings → Connections. Authenticate provider CLIs inside the environment that runs them. A host app or GitHub login does not authenticate providers inside WSL.

## Keyboard and remote access

For desktop access, finish Tailscale sign-in on the Windows host, then run `pwsh -File ./setup-remote-desktop.ps1 -Enable` in **Administrator PowerShell 7** on that host. Use `-Enable -WhatIf` to preview. It configures supported native RDP with automatic startup, NLA/TLS, existing allowed users, and a firewall rule restricted to the active Tailscale adapter/address. It refuses unsupported editions, managed-policy denial, an offline tailnet, disabled/broad-default firewalls, and ambiguous existing custom RDP allows before changing RDP settings. Windows Home cannot host native RDP. This native command is intentionally separate from WSL; see [desktop access](docs/tailscale.md#desktop-access).

Use Omarchy's terminal chords inside tmux and Herdr: `Ctrl+Space`, Alt+Enter splits, Ctrl+Alt+arrow pane focus, and aligned tab/session actions. If Windows Terminal or another host app intercepts a chord, clear that host binding in its supported settings and verify delivery in the multiplexer. Do not remap the whole Windows desktop or assume Linux can configure host input.

Install Tailscale on the Windows host for normal access to that machine; see [Tailscale setup](docs/tailscale.md). WSL is a separate environment, so host connectivity alone does not publish its SSH server. Choose Both in `groundwork-configure` when you want tmux lessons alongside Herdr.

## Updates

Inside WSL2, run `update-all` from any directory for normal Groundwork tool
updates and maintenance. Run `groundwork-update` to synchronize and apply only
Unix configuration using saved settings. Configuration applies can install newly
declared tools; they do not request routine upgrades or cleanup. Existing
installations receive the new command on their next successful `update-all`.
Use `groundwork-configure` to change preferences.

The visible `groundwork-mac` engine checkout remains the update owner. This
entry-point checkout contains setup and Windows-host guidance; daily maintenance
does not require pulling it or rerunning bootstrap. Review local changes before
`git pull --ff-only` when you need newer bootstrap or host scripts.

WSL commands do not update Windows apps, change host permissions, or update
Windows itself. Use Windows Update and each app's supported Windows updater on
the host. Linux distribution packages inside WSL keep their supported package
manager. Do not run two competing Tailscale or agent-server installations
without deliberately choosing their ownership.

## License

[MIT](LICENSE), matching the Groundwork family.

## Common developer setup and macOS containers

The family uses one developer tool set across personal and managed machines, with independent identity and optional-app preferences. See the [shared setup guide](https://github.com/jasondockery/groundwork-core/blob/main/docs/developer-setup.md) for tool and platform ownership.

For a macOS machine, Groundwork recommends Colima plus the Docker CLI. The single [Docker Desktop to Colima guide](https://github.com/jasondockery/groundwork-mac/blob/main/docs/docker-desktop-to-colima.md) covers migration scenarios, data transfer, verification, rollback, and Docker Desktop uninstallation after acceptance. This recommendation applies to macOS; this repository’s Linux, WSL, or Omarchy environment keeps its native container path.

## Native Windows apps

Run `pwsh -File ./install-host-apps.ps1` on the Windows host to review the official Tailscale, Cursor, Claude, ChatGPT, FreeTube, and Brave packages. Brave's winget id is `Brave.Brave`. PowerShell 7 and Microsoft App Installer (`winget`) are required. `pwsh -File ./install-host-apps.ps1 -Install -WhatIf` previews the actions. `-Install` requests the latest available package versions and accepts their source and package agreements. Every package has a ten-minute deadline. Failed or policy-blocked operations are reported rather than called current. Store availability and organization policy remain authoritative. Open each app to verify its version, and finish sign-in for Tailscale, Cursor, Claude, and ChatGPT. FreeTube and Brave have no account.

Windows does not let a program choose the default browser. After Brave installs, the script prints `pwsh -File ./install-host-apps.ps1 -SetDefaultBrowser`. Run that command in 64-bit PowerShell 7. It opens Windows Settings on Brave's default-apps page so you can confirm Brave. It reads Brave's registration name from the registry, including a per-user `Brave.<suffix>` name. It does not set the default itself.

Shared Brave policies are pinned with the `core` submodule at groundwork-core v0.7.0. They are read from `core/browser/brave.json`. `pwsh -File ./install-host-apps.ps1 -ApplyBrowserPolicy` writes those values under `HKLM\Software\Policies\BraveSoftware\Brave`. Run that command in 64-bit Administrator PowerShell 7. Add `-WhatIf` to list the values without writing them. Values already under that key that are not in the spec are left alone. If `core` is missing, run `git submodule update --init`.

The script does not uninstall another browser and does not delete profile data. When Google Chrome is installed, or Chrome or Edge is the current default, it prints one line for Brave's importer at `brave://settings/importData`. That line is bookmarks and history. Passwords stay in Bitwarden. Bitwarden is the only extension the spec offers. The script prints its Web Store page and does not install it.

The native host script is separate from WSL setup. Codex CLI, Claude Code, Grok Build, and OpenCode run inside WSL through the shared engine and need provider authentication there. Tailscale is installed on the host by the script; the WSL package does not start or enroll another daemon automatically. Windows apps update through their official updater, Microsoft Store, or the supported winget command. No Windows app is installed from a WSL shell.
