# Tailscale on Windows and WSL2

Read the [shared Tailscale guide](https://github.com/jasondockery/groundwork-core/blob/main/docs/tailscale.md) for policy, MagicDNS, MFA, device approval, expiry, and two-way checks. This page owns the Windows/WSL boundary only.

Install the official Tailscale Windows app on the host, sign in interactively to the same personal tailnet as your other devices, and approve the device. Let that app own its Windows service and DNS. An unattended-mode choice changes whether it runs after logout; make that choice deliberately and verify reboot behavior before depending on remote access.

For incoming terminal access to Windows, enable Windows OpenSSH Server for the intended local account and authorize its SSH key. Apply a narrow host firewall rule for the chosen access path as well as the tailnet's network policy. The Windows app cannot serve Tailscale SSH; an SSH check-mode rule applies to Tailscale SSH servers, not ordinary Windows OpenSSH authentication. Do not expose the port through your router.

WSL2 is a separate Linux environment. Reaching Windows through Tailscale does not automatically make a WSL SSH server reachable. The straightforward route is SSH to the Windows host, then enter the intended WSL distribution with `wsl -d DISTRIBUTION`. A separately enrolled WSL node is a deliberate alternative: review its service, DNS, lifecycle, and access policy rather than starting an extra daemon by default.

From Windows, ordinary `ssh LOCAL_USER@MACHINE` reaches an approved Omarchy/Linux destination using its local login and MagicDNS name. Test every required direction, including after logout/reboot, before treating remote access as accepted. Keep T3 Code Nightly's agent environment and credentials on the machine/distro where they run.
