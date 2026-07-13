# SCLF — ScreenConnect Client Fix for Linux

Fix for getting the ScreenConnect (ConnectWise Control) Client — the
Host/support-session client — working on Linux desktops. Verified on
CachyOS (2026-07-11), Debian 13 KDE (2026-07-13), and Arch Linux (2026-07-13).

## How to use this repo — pick one

- **Option A (recommended):** give `agent.md` to an AI assistant that can run
  commands on your machine (Claude Code or similar) and let it do everything.
  All the technical detail is in that file.
- **Option B:** follow the steps below by hand.

## The problem

The vendor's `ScreenConnect.ClientSetup.sh` installer is broken on Linux
desktops in two different ways:

- **Arch-based distros:** the installer silently does nothing at all.
- **Debian (and similar):** the client installs and the first session opens,
  but clicking a session join link in the browser afterwards does nothing —
  or the browser offers to download the installer again.

Both come from vendor-installer bugs, not from your system. `agent.md` has
the full explanation.

## The fix

1. Get `ScreenConnect.ClientSetup.sh` from your ScreenConnect server (it
   downloads automatically when you try to join a session from the web page).
2. Install the dependencies for your distro:

   ```sh
   # Debian/Ubuntu
   sudo apt install default-jre desktop-file-utils

   # Arch/CachyOS
   sudo pacman -S --needed jre-openjdk desktop-file-utils xdg-utils
   ```

3. Put the installer next to `install-screenconnect-linux.sh` (or pass its
   path as an argument) and run — **never with sudo**:

   ```sh
   sh install-screenconnect-linux.sh
   ```

4. **Restart your browser.**

## Verifying

- The ScreenConnect Client window opens at the end of the install.
- After the browser restart, joining a session from the ScreenConnect web
  page asks once "always open with ScreenConnect?" — allow it. Every join
  after that launches the client immediately, no prompts.
- If nothing opens, check `~/.local/share/applications/<packageName>-logs`.

## Notes

- **Known cosmetic side effect (KDE):** if your taskbar browser icon is
  KDE's dynamic "preferred browser" pin and you never explicitly set a
  default browser, the cache rebuild during the fix can make that pin
  re-resolve to another installed browser (seen once: Firefox pin turned
  into Konqueror). Harmless — re-pin your browser, or set it explicitly
  first in System Settings → Default Applications → Web browser.
- Per-user install, no root needed for the script itself. Running the vendor
  installer (or this script) with sudo installs the client uselessly for root
  — that's one of the failure modes this repo exists to prevent.
- The script reads the instance/package name from the installer payload, so
  it works for any ScreenConnect instance's Host-client installer.
- Reinstalling later? Just run the script again — it re-repairs the
  registration every time.
- Unattended agents (Access/Guest installs) are a different code path and are
  **not** covered by this fix.
- Do not commit `ScreenConnect.ClientSetup.sh` anywhere — it's proprietary
  (gitignored here).
