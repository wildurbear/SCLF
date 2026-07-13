# Agent instructions: fix ScreenConnect Client on Linux (any distro)

You are helping a user get the ScreenConnect (ConnectWise Control) Client —
the **Host/support-session client** — working on a Linux desktop, so that
clicking a session join link in any browser launches the installed client.
This procedure is proven: the Arch path was verified on CachyOS (client
25.9.5.9483, 2026-07-11); the registration repair was verified on Debian 13
(trixie) KDE with Firefox (2026-07-13). Follow it as written; only debug if
a step fails.

**Machine-specific values (instance IDs, package names, paths, versions) in
this document are examples from the reference machines. NEVER assume them —
read every such value off the user's system.** The ScreenConnect instance ID
(e.g. `e414e1993a80edf3`) differs per ScreenConnect server.

## Operating rules

1. Read facts off the machine before acting — never invent paths, IDs, or
   versions.
2. One change at a time; verify each step's expected outcome before the next.
3. NEVER run the vendor installer or the fix script with sudo — the client is
   a per-user install into `$HOME/.local/share/applications/`. A sudo run
   installs it uselessly for root (and errors on `/root/.config`).
4. The installer .sh is proprietary. Never commit it to a repo or upload it.
5. If a signature doesn't match what Step 0 expects, stop and diagnose —
   don't force this playbook onto a different problem.

## Background: the two vendor bugs (do not re-research this)

`ScreenConnect.ClientSetup.sh` is a ~45 MB self-extracting POSIX-sh installer
with binary payloads appended after the script, delimited by marker lines
(`tar.gz__commencement` / `tar.gz__completion` etc.). For Host clients the
only payload that matters on Linux is the tar.gz: a per-user Java Swing app
(needs a JRE, not headless) with the vendor's own 27-line
`ClientInstaller.sh`, which copies files to
`~/.local/share/applications/<packageName>/`, writes
`<packageName>.desktop` with `MimeType=x-scheme-handler/sc-<instanceId>`,
registers that URL scheme, and launches the session.

**Bug 1 — Arch-based distros (silent no-install):** the outer script's
`determinePackageType()` only checks `which rpm` / `which pkgutil` /
`which dpkg`. On Arch all are absent → it returns an empty string → the
script calls a nonexistent function and exits silently. The .deb/.rpm
payloads are dead weight for Host clients anyway; the check is only a broken
"am I on Linux?" proxy.

**Bug 2 — Debian/KDE (browser links dead after install):**
`ClientInstaller.sh` line 23 runs
`xdg-mime default <FULL PATH to .desktop> x-scheme-handler/sc-<id>`.
The freedesktop spec says mimeapps.list values are desktop-file **IDs**
(`<packageName>.desktop`), not paths. On Debian KDE, xdg-mime's KDE branch
aborts (`qtpaths` not shipped) and its generic fallback writes the passed
path **verbatim** into `~/.config/mimeapps.list`. GIO — which is what
Firefox asks to resolve the scheme — cannot resolve a path value and reports
no handler, so clicking a join link does *nothing* (no dialog, no error).
Additionally line 22 (`update-desktop-database`) fails if
`desktop-file-utils` isn't installed, so `mimeinfo.cache` is never built
(affects handler *discovery*; Firefox's default lookup works without it, but
install it anyway). The vendor installer prints these failures and continues
— and line 25 launches the session directly, which is why the first connect
always works and masks the breakage.

Why both bugs get one fix: extracting the tar.gz ourselves bypasses Bug 1 on
every distro (on Debian it's exactly equivalent to what the vendor script
does), and repairing the mimeapps.list entry after install fixes Bug 2 —
as a no-op where registration landed correctly. Because the repair runs
after every (re)install, the fix is durable by construction: reinstalls
through this script can't re-break it.

## Step 0 — confirm this is actually the user's problem

Expected signatures (any of):
- Arch: `sh ScreenConnect.ClientSetup.sh` produces no output, no install, no
  window.
- Debian: install "worked" (session opened) but printed
  `update-desktop-database: not found` and/or `qtpaths: not found`, and
  browser join links now do nothing or re-offer the .sh download.
- Any distro: check the registration state —
  ```sh
  ls ~/.local/share/applications/ | grep -i connectwisecontrol
  cat ~/.config/mimeapps.list 2>/dev/null | grep 'x-scheme-handler/sc-'
  ```
  A value containing `/home/` (absolute path) instead of a bare
  `connectwisecontrol-<id>.desktop` ID is Bug 2, confirmed. Verify with:
  ```sh
  gio mime x-scheme-handler/sc-<id-read-from-the-file-above>
  ```
  "No default applications" while the .desktop file exists = confirmed.

If the user's problem is an **unattended agent** (Access/Guest, installs a
system service via .deb/.rpm) — STOP, out of scope. If the client installs
but crashes at launch, that's a Java/runtime problem, not this playbook
(see "If it fails").

## Procedure

1. Confirm the user has `ScreenConnect.ClientSetup.sh` (their ScreenConnect
   server offers it when joining a session from the web page). Note its path.

2. Install dependencies. Java must be the GUI-capable variant (Swing), not
   headless. `desktop-file-utils` is recommended on all distros (builds
   `mimeinfo.cache`; also silences the vendor installer's line-22 error):

   ```sh
   # Debian/Ubuntu
   sudo apt install default-jre desktop-file-utils
   # Arch/CachyOS
   sudo pacman -S --needed jre-openjdk desktop-file-utils xdg-utils
   # other distros: detect the package manager and find equivalents
   ```

3. Run the fix script — as the normal user, never sudo:

   ```sh
   sh install-screenconnect-linux.sh /path/to/ScreenConnect.ClientSetup.sh
   ```

   What it does (if you must recreate it): find the marker line numbers with
   `grep -anF -m1 'tar.gz__commencement'` / `'tar.gz__completion'` (never
   hardcode line numbers — they differ per instance); extract strictly
   between them with `tail -n+START | head -nCOUNT`; strip the single
   trailing newline (`perl -i -0pe 's/\n\Z//'` — required or gunzip fails);
   `tar -xzf` to /tmp; run `sh /tmp/<packageName>/ClientInstaller.sh`
   (packageName = the tarball's top-level directory); then repair
   registration: read the scheme from the `MimeType=` line of
   `~/.local/share/applications/<packageName>.desktop` and force the
   mimeapps.list entry to `x-scheme-handler/sc-<id>=<packageName>.desktop`
   (bare ID, replacing any absolute-path value; create the
   `[Default Applications]` section if absent); run
   `update-desktop-database ~/.local/share/applications` and `kbuildsycoca6`
   where available.

4. Verify registration immediately (no browser needed):

   ```sh
   gio mime "$(grep -m1 '^MimeType=' ~/.local/share/applications/connectwisecontrol-*.desktop | head -n1 | cut -d= -f2 | tr -d ';')"
   ```

   Expected: `Default application for “x-scheme-handler/sc-<id>”:
   connectwisecontrol-<id>.desktop`. "No default applications" = the repair
   step didn't take; inspect `~/.config/mimeapps.list` by hand.

5. **Restart the browser** (all of them that will be used). Browsers cache
   scheme-handler lookups per session; skipping this makes a correct fix look
   broken.

6. Success criteria: the ScreenConnect Client window opened at the end of
   step 3 (vendor installer auto-launches the session), AND after the
   restart, clicking Join on the ScreenConnect web page prompts once
   ("always open with ScreenConnect?") and then launches the client — and
   every subsequent join launches with no prompt at all.

## The decisive test (when the user wants proof, not hope)

From clean state (uninstall: delete
`~/.local/share/applications/connectwisecontrol-<id>*` and the
`x-scheme-handler/sc-<id>` line from `~/.config/mimeapps.list`): run steps
2–5 once, then join from Firefox AND Chromium — each must work on the first
click (after its one "always allow" prompt). Reboot; join again. Rerun the
script (reinstall); join again. All must work with zero manual intervention.

## Hardening / durability

- The vendor installer re-writes the broken mimeapps.list value on every
  reinstall. That is why the repair lives in the install script: always
  install/reinstall through `install-screenconnect-linux.sh`, never through
  the bare vendor .sh.
- System updates don't touch `~/.config/mimeapps.list` or
  `~/.local/share/applications/` — the fix persists.
- A NEW ScreenConnect instance (different server) = different `sc-<id>`
  scheme = a fresh install through the script; instances coexist.

## Reverting

```sh
rm -rf ~/.local/share/applications/connectwisecontrol-<id>*
sed -i '/^x-scheme-handler\/sc-<id>=/d' ~/.config/mimeapps.list
command -v update-desktop-database && update-desktop-database ~/.local/share/applications
```

(Read `<id>` off the machine. The dependency packages are standard and safe
to keep.)

## If it fails

Work these ONE at a time, logging what each shows:

1. Read `~/.local/share/applications/<packageName>-logs` first — the
   launcher redirects all output there.
2. `gio mime` shows no default (step 4 failed) → inspect
   `~/.config/mimeapps.list`: the entry must be exactly
   `x-scheme-handler/sc-<id>=connectwisecontrol-<id>.desktop` under
   `[Default Applications]`. Fix by hand, re-verify with `gio mime`.
3. gio resolves but Firefox still does nothing → confirm the browser was
   actually restarted; then check `~/.mozilla/firefox/*/handlers.json` for a
   stale `sc-<id>` entry (backup, remove it, restart Firefox).
4. Firefox works, Chromium doesn't → ensure `desktop-file-utils` is
   installed and `update-desktop-database ~/.local/share/applications` was
   run (Chromium leans on `mimeinfo.cache` for discovery); on KDE also run
   `kbuildsycoca6`.
5. `gzip: invalid magic` during extraction → the trailing-newline strip was
   skipped or the marker-line math is off by one.
6. `java: command not found` → step 2 skipped or headless variant installed.
7. `UnsatisfiedLinkError` in the log → the .so files must sit in the install
   dir; check `~/.local/share/applications/<packageName>/`.
8. Installs but no window on Wayland → ensure XWayland (`xorg-xwayland` on
   Arch); on tiling WMs try `_JAVA_AWT_WM_NONREPARENTING=1`.
9. A prior sudo run leaves junk in `/root/.local/share/applications/` —
   harmless to the user session, but clean it:
   `sudo rm -rf /root/.local/share/applications/connectwisecontrol-<id>*`

## Known cosmetic side effect (KDE)

The script runs `update-desktop-database` (possibly building
`mimeinfo.cache` for the first time on the machine) and `kbuildsycoca6`.
On KDE, taskbar browser icons are often the dynamic `preferred://browser`
pin; if the user has NO explicit default browser set (no `text/html` /
`x-scheme-handler/http` entries in `~/.config/mimeapps.list`) and multiple
browsers are installed, the cache rebuild can make that pin re-resolve to a
different browser (observed on Debian 13 KDE: Firefox pin became Konqueror).
Verified harmless. Remedies: re-pin the browser (creates a concrete pin), or
set the default browser explicitly beforehand (System Settings → Default
Applications, or `xdg-settings set default-web-browser <browser>.desktop`).
Warn the user about this rather than letting them think the fix broke
something.

## Scope limits

- **Host/support-session clients only.** Unattended access agents
  (Access/Guest) use the .deb/.rpm payloads with an init service and are not
  fixed by this procedure.
- Verified on: CachyOS/KDE (Arch path) and Debian 13/KDE with Firefox
  (registration repair). Other distros/DEs should work by the same
  mechanisms — detect, verify each step, don't assume.
