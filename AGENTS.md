# Agents

This repo owns the Windows/WSL2 entry point and host-versus-Linux guidance. The shared Unix provisioning implementation currently lives in `groundwork-mac`; change managed files there instead of copying them here. Do not apply Linux home files to the Windows host or an Omarchy machine.

Use [Compass](https://github.com/jasondockery/compass/blob/main/COMPASS.md) and its applicable skills for shared engineering guidance. Use [groundwork-core](https://github.com/jasondockery/groundwork-core) for shared operational docs and tailnet policy. These links are references, not a claim of receipt-verified projection. Keep original `groundwork` unchanged and available for curriculum and historical context.

Omarchy's keybindings and conventions are the target where they fit. T3 Code Nightly and Herdr must stay available inside WSL2, with providers authenticated there. Native Windows app installation and permissions are separate, explicit operations. Do not restore historical Groundwork shortcuts as the target.

Parse arguments before side effects. Help and invalid input must not mutate anything. Preserve Windows and WSL configuration, SSH credentials, Git identities, and old checkouts during migration. Test wrappers with isolated fixtures; never claim native Windows, WSL, desktop, or remote acceptance from a Linux-only fixture.
