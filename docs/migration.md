# Move an existing Windows/WSL Groundwork installation

Use the [shared migration guide](https://github.com/jasondockery/groundwork-core/blob/main/docs/migrating-from-groundwork.md) for backups, local edits, preview, applying the new source, acceptance, and rollback. Keep the original checkout and its remote unchanged.

In PowerShell, inspect `wsl --list --verbose`. Enter the same WSL2 distribution where Groundwork was installed. Clone this repo into a new directory inside its Linux filesystem and run `bash bootstrap.sh --prepare-only`. The visible shared engine defaults to `~/code/groundwork-mac` inside that distribution; nothing is applied by this preparation step.

Use that Linux engine path in the shared guide's chezmoi preview and apply steps. Keep the distro's stored answers and user overrides. Do not copy Windows home-directory configuration into WSL or run the Linux apply on Windows itself. Existing native Windows tools and their credentials remain separate.

After acceptance, choose Both in `groundwork-configure` when you want Herdr alongside tmux. Check that Windows Terminal delivers the Omarchy-aligned chords; clear only conflicting host shortcuts through its supported settings. Install the optional native T3 Code Nightly UI from the official releases if desired, then connect it to this WSL distribution through its Connections settings.

The previous Groundwork environment supported WSL2 rather than a native Windows shell. A different historical host setup needs a separate inventory before changing it; this wrapper does not silently convert it.
