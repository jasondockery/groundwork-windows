# Tailscale on Windows and WSL2

Read the [shared Tailscale guide](https://github.com/jasondockery/groundwork-core/blob/main/docs/tailscale.md) for policy, MagicDNS, MFA, device approval, expiry, and two-way checks. This page owns the Windows/WSL boundary only.

Use the explicit [`install-host-apps.ps1`](../install-host-apps.ps1) host installer, or install the official Tailscale Windows app on the host, sign in interactively to the same personal tailnet as your other devices, and approve the device. Let that app own its Windows service and DNS. An unattended-mode choice changes whether it runs after logout; make that choice deliberately and verify reboot behavior before depending on remote access.

For incoming terminal access to Windows, enable Windows OpenSSH Server for the intended local account and authorize its SSH key. Apply a narrow host firewall rule for the chosen access path as well as the tailnet's network policy. The Windows app cannot serve Tailscale SSH; an SSH check-mode rule applies to Tailscale SSH servers, not ordinary Windows OpenSSH authentication. Do not expose the port through your router.

WSL2 is a separate Linux environment. Reaching Windows through Tailscale does not automatically make a WSL SSH server reachable. The straightforward route is SSH to the Windows host, then enter the intended WSL distribution with `wsl -d DISTRIBUTION`. A separately enrolled WSL node is a deliberate alternative: review its service, DNS, lifecycle, and access policy rather than starting an extra daemon by default.

From Windows, ordinary `ssh LOCAL_USER@MACHINE` reaches an approved Omarchy/Linux destination using its local login and MagicDNS name. Test every required direction, including after logout/reboot, before treating remote access as accepted. Keep T3 Code Nightly's agent environment and credentials on the machine/distro where they run.

## Desktop access

On a supported Windows Pro, Enterprise, Education, or Server host, first complete local Tailscale sign-in and device approval. In Administrator PowerShell 7, inspect and run `pwsh -File ./setup-remote-desktop.ps1 -Enable`. The default invocation shows a plan; `-Enable -WhatIf` previews without changing Windows. Native RDP starts automatically after setup, without starting a second daemon in WSL. The host's existing RDP port and allowed users remain selected. Use a Windows account already allowed to sign in remotely; a Windows Hello PIN is not a reusable remote account password.

The command requires an enabled default-block Windows firewall, rejects custom RDP-capable allow rules that need owner reconciliation, replaces only its own scoped allow, disables the built-in broad `RemoteDesktop-*` allows, and keeps NLA/TLS enabled. It does not add accounts to Remote Desktop Users or disable organizational policy. Keep an independent local recovery path while changing remote access. If a later step fails, completed settings remain; inspect the error and rerun rather than assuming success.

Use **Windows App** on macOS or another supported RDP client, with the destination's MagicDNS name and the port printed by setup (normally TCP 3389). Add only that port to the [shared owner-scoped network grant](https://github.com/jasondockery/groundwork-core/blob/main/docs/tailscale.md#agent-tools-and-screens), authenticate as an allowed Windows user, and verify the server certificate. macOS Screen Sharing is a VNC client and is not the Windows RDP client. For an Omarchy destination, use its WayVNC setup and a VNC client instead.

Verify screen/control from another approved machine and again after reboot. Rerun the host command if Tailscale is re-enrolled or its adapter/address changes; the old scoped rule deliberately does not widen itself. Disable Remote Desktop in Windows Settings to turn the server off; remove only the `Groundwork-RDP-Tailscale` firewall rule if retiring this setup. Do not enable every built-in firewall rule or open a public router port. Windows Home needs a separately chosen supported remote-desktop product; this repo never patches Windows to unlock unsupported RDP hosting.
