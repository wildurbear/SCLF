#!/bin/sh
# install-screenconnect-linux.sh — SCLF unified fix
#
# Installs the ScreenConnect (ConnectWise Control) Host/support-session client
# on any Linux distro and repairs the browser URL-scheme registration, fixing
# two independent vendor-installer bugs:
#
#  1. Arch-based distros: the installer's package detection only knows
#     rpm/dpkg/pkgutil, so on Arch it silently does nothing. We bypass it by
#     extracting the embedded tar.gz payload ourselves (exactly the way the
#     vendor script does) and running the vendor's own ClientInstaller.sh.
#     For Host clients this payload is a per-user Java app — no root needed.
#
#  2. Debian (and any distro without qtpaths on KDE): the vendor installer
#     registers the sc-<instanceId>: URL scheme by passing the FULL PATH of
#     its .desktop file to `xdg-mime default`; xdg-mime's generic fallback
#     writes that path verbatim into ~/.config/mimeapps.list, where the
#     freedesktop spec requires a desktop-file ID. GIO (what Firefox asks to
#     resolve the scheme) cannot resolve a path value, so clicking a session
#     join link silently does nothing. We rewrite the entry to the bare ID
#     after installing — a no-op on systems where registration landed right.
#
# Usage:  sh install-screenconnect-linux.sh [path/to/ScreenConnect.ClientSetup.sh]
#         (defaults to ScreenConnect.ClientSetup.sh next to this script)
#
# Do NOT run with sudo — this is a per-user install; sudo would install the
# client uselessly into /root.
#
# Requires: java (Swing GUI, not headless), tar, perl, sed, grep.
# Recommended: desktop-file-utils (builds mimeinfo.cache for app discovery).
#   Debian/Ubuntu: sudo apt install default-jre desktop-file-utils
#   Arch/CachyOS:  sudo pacman -S --needed jre-openjdk desktop-file-utils xdg-utils

set -eu

if [ "$(id -u)" = 0 ]; then
	echo "error: do not run as root/sudo — the client is a per-user install" >&2
	exit 1
fi

installerPath="${1:-$(dirname "$0")/ScreenConnect.ClientSetup.sh}"

if [ ! -f "$installerPath" ]; then
	echo "error: installer not found: $installerPath" >&2
	echo "get ScreenConnect.ClientSetup.sh from your ScreenConnect web page (offered when joining a session)" >&2
	exit 1
fi

if ! command -v java >/dev/null 2>&1; then
	echo "error: java not found — install it first:" >&2
	echo "  Debian/Ubuntu: sudo apt install default-jre" >&2
	echo "  Arch/CachyOS:  sudo pacman -S --needed jre-openjdk" >&2
	exit 1
fi

# --- 1. Extract the embedded tar.gz payload (vendor-equivalent method) ------

startLine=$(($(grep -anF -m1 'tar.gz__commencement' "$installerPath" | cut -d: -f1) + 1))
endLine=$(grep -anF -m1 'tar.gz__completion' "$installerPath" | cut -d: -f1)

if [ "$startLine" -le 1 ] || [ -z "$endLine" ]; then
	echo "error: tar.gz payload markers not found in $installerPath" >&2
	exit 1
fi

payloadPath=$(mktemp -t screenconnect-payload-XXXXXX)
trap 'rm -f "$payloadPath"' EXIT

tail "-n+$startLine" "$installerPath" | head "-n$((endLine - startLine))" > "$payloadPath"
# The build appends a newline to the binary payload; the vendor strips it the
# same way before untarring (SCP:33423 comment in their script). Required.
perl -i -0pe 's/\n\Z//' "$payloadPath"

packageName=$(tar -tzf "$payloadPath" | head -n1 | tr -d /)
echo "extracting payload for package: $packageName"

tar -xzf "$payloadPath" --directory /tmp

# --- 2. Run the vendor's own installer (per-user; also launches the session)

# Note: on Debian this may print "update-desktop-database: not found" and/or
# "qtpaths: not found" — expected; step 3 repairs what those failures break.
sh "/tmp/$packageName/ClientInstaller.sh"

rm -rf "/tmp/$packageName"

# --- 3. Repair the URL-scheme registration ----------------------------------

appsDir="$HOME/.local/share/applications"
desktopFileId="$packageName.desktop"
desktopFilePath="$appsDir/$desktopFileId"
mimeappsPath="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"

if [ ! -f "$desktopFilePath" ]; then
	echo "error: expected desktop entry missing: $desktopFilePath" >&2
	exit 1
fi

# e.g. x-scheme-handler/sc-e414e1993a80edf3 — read it off the installed file,
# never assume the instance id.
scheme=$(grep -m1 '^MimeType=' "$desktopFilePath" | cut -d= -f2 | tr -d ';')

if [ -z "$scheme" ]; then
	echo "error: no MimeType= line in $desktopFilePath" >&2
	exit 1
fi

mkdir -p "$(dirname "$mimeappsPath")"
touch "$mimeappsPath"

if grep -q "^$scheme=" "$mimeappsPath"; then
	# Replace whatever value is there (vendor writes an absolute path) with
	# the spec-correct desktop-file ID.
	sed -i "s|^$scheme=.*|$scheme=$desktopFileId|" "$mimeappsPath"
else
	grep -q '^\[Default Applications\]' "$mimeappsPath" || printf '[Default Applications]\n' >> "$mimeappsPath"
	sed -i "\|^\[Default Applications\]|a $scheme=$desktopFileId" "$mimeappsPath"
fi

# Rebuild caches where the tools exist (harmless no-ops elsewhere).
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$appsDir" || true
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true

# --- 4. Verify ---------------------------------------------------------------

echo
echo "registered:   $scheme -> $desktopFileId"
if command -v gio >/dev/null 2>&1; then
	gio mime "$scheme" | head -n1
fi
echo "installed to: $appsDir/$packageName"
echo "launch log:   $appsDir/$packageName-logs"
echo
echo "IMPORTANT: restart your browser before clicking a session join link"
echo "(browsers cache scheme-handler lookups per session)."
