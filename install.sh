#!/bin/sh
# Install or upgrade LAIR on macOS or Linux, without sudo:
#
#   curl -fsSL https://lair.mle.wtf/install.sh | sh
#
# Downloads the release tarball for this OS and architecture plus SHA256SUMS,
# refuses anything whose checksum does not match, and puts `lair` in
# $LAIR_INSTALL_DIR (default ~/.local/bin). Rerunning it upgrades in place.
#
# Linux x86_64 has two builds: `desktop` (glibc, tray and chat window, needs
# GTK 3 and WebKitGTK 4.1) and `headless` (static, for servers). The desktop
# one is picked when a graphical session is present and GTK 3 is installed;
# LAIR_FLAVOR=desktop|headless forces either. An upgrade keeps the flavor
# already installed. Linux arm64 is headless only for now.
#
# LAIR_RELEASE_BASE points it at another release (a staging one, or a local
# server for testing); it is the directory the assets are downloaded from.
say() { printf '%s\n' "$*"; }
die() {
	printf 'lair install: %s\n' "$*" >&2
	exit 1
}

fetch() {
	# HTTPS only, redirects included, when the base is HTTPS; a plain-http
	# LAIR_RELEASE_BASE (a local test server) is taken as given.
	tls=
	case $BASE in https://*) tls=1 ;; esac
	if command -v curl >/dev/null 2>&1; then
		if [ -n "$tls" ]; then
			curl -fsSL --retry 3 --proto '=https' --proto-redir '=https' --tlsv1.2 -o "$2" "$1" || die "download failed: $1"
		else
			curl -fsSL --retry 3 -o "$2" "$1" || die "download failed: $1"
		fi
		return
	fi
	if command -v wget >/dev/null 2>&1; then
		if [ -n "$tls" ]; then
			wget -q --https-only -O "$2" "$1" || die "download failed: $1"
		else
			wget -q -O "$2" "$1" || die "download failed: $1"
		fi
		return
	fi
	die "need curl or wget to download LAIR."
}

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d ' ' -f 1
		return
	fi
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d ' ' -f 1
		return
	fi
	die "need sha256sum or shasum to verify the download."
}

has_gtk3() {
	# glibc's cache is the answer when there is one; the paths are for a
	# system whose ldconfig cannot list it.
	if cache=$( (ldconfig -p || /sbin/ldconfig -p) 2>/dev/null) && [ -n "$cache" ]; then
		printf '%s\n' "$cache" | grep -q 'libgtk-3\.so\.0'
		return
	fi
	for d in /usr/lib/x86_64-linux-gnu /usr/lib64 /usr/lib /lib/x86_64-linux-gnu /lib64; do
		[ -e "$d/libgtk-3.so.0" ] && return 0
	done
	return 1
}

# Linux x86_64 only: which build to fetch, and say why.
pick_flavor() {
	case $FLAVOR in
	desktop | headless)
		say "Installing the $FLAVOR build (LAIR_FLAVOR)."
		return
		;;
	"") ;;
	*) die "LAIR_FLAVOR must be desktop or headless, not '$FLAVOR'." ;;
	esac
	if [ -e "$DIR/lair" ]; then
		# The marker this script leaves; for an install without one, the
		# desktop build links GTK and the headless one is static.
		FLAVOR=$(cat "$DIR/.lair-flavor" 2>/dev/null || true)
		case $FLAVOR in
		desktop | headless) ;;
		*) if grep -q 'libgtk-3\.so' "$DIR/lair" 2>/dev/null; then FLAVOR=desktop; else FLAVOR=headless; fi ;;
		esac
		say "Upgrading the $FLAVOR build already in $DIR."
	elif [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
		FLAVOR=headless
		say "No desktop session (\$DISPLAY and \$WAYLAND_DISPLAY are unset): installing the headless build."
	elif ! has_gtk3; then
		FLAVOR=headless
		say "A desktop session but no GTK 3 (libgtk-3.so.0): installing the headless build."
	else
		FLAVOR=desktop
		say "Desktop session with GTK 3 found: installing the desktop build (tray and chat window)."
	fi
	other=desktop
	[ "$FLAVOR" = desktop ] && other=headless
	say "  For the $other build instead: curl -fsSL $SCRIPT_URL | LAIR_FLAVOR=$other sh"
}


# Everything runs from here, called on the last line, so a download cut
# short by the network (`curl | sh`) defines functions and runs nothing.
main() {
	set -eu

	BASE=${LAIR_RELEASE_BASE:-https://github.com/mle-wtf/lair-releases/releases/latest/download}
	DIR=${LAIR_INSTALL_DIR:-$HOME/.local/bin}
	FLAVOR=${LAIR_FLAVOR:-}
	SCRIPT_URL=https://lair.mle.wtf/install.sh

	os=$(uname -s)
	arch=$(uname -m)
	case $os in
	Darwin) asset=lair-macos-universal.tar.gz ;;
	Linux)
		case $arch in
		x86_64 | amd64)
			pick_flavor
			asset=lair-linux-x86_64.tar.gz
			[ "$FLAVOR" = desktop ] && asset=lair-linux-x86_64-desktop.tar.gz
			;;
		aarch64 | arm64)
			[ "$FLAVOR" = desktop ] && die "there is no desktop build for Linux arm64 yet; LAIR_FLAVOR=headless or unset."
			say "Linux arm64: installing the headless build (there is no arm64 desktop build yet)."
			asset=lair-linux-arm64.tar.gz
			;;
		*) die "unsupported Linux architecture '$arch'. LAIR ships for x86_64 and arm64 (aarch64)." ;;
		esac
		;;
	*) die "unsupported OS '$os'. This script is for macOS and Linux; on Windows run install.ps1." ;;
	esac

	tmp=$(mktemp -d 2>/dev/null || mktemp -d -t lair-install)
	staged=""
	cleanup() {
		rm -rf "$tmp"
		[ -z "$staged" ] || rm -f "$staged"
	}
	trap cleanup EXIT
	trap 'exit 1' INT TERM HUP

	say "Downloading $asset ..."
	fetch "$BASE/$asset" "$tmp/$asset"
	fetch "$BASE/SHA256SUMS" "$tmp/SHA256SUMS"

	want=$(awk -v f="$asset" '$2 == f || $2 == "*" f { print $1; exit }' "$tmp/SHA256SUMS")
	[ -n "$want" ] || die "SHA256SUMS has no entry for $asset."
	got=$(sha256 "$tmp/$asset")
	[ "$got" = "$want" ] || die "checksum mismatch for $asset (expected $want, got $got). Nothing was installed."

	mkdir -p "$tmp/x"
	tar -xzf "$tmp/$asset" -C "$tmp/x"
	[ -f "$tmp/x/lair" ] || die "$asset has no ./lair in it."
	chmod 755 "$tmp/x/lair"

	# A desktop build that cannot load here (a missing library, an older glibc)
	# exits 127 from the loader, 126 if it cannot be executed at all; anything
	# else means it ran (`lair help` prints its usage and exits 2).
	if [ "$asset" = lair-linux-x86_64-desktop.tar.gz ]; then
		rc=0
		err=$("$tmp/x/lair" help 2>&1 >/dev/null) || rc=$?
		[ "$rc" -ne 126 ] && [ "$rc" -ne 127 ] || die "the desktop build does not run on this machine (exit $rc: $(printf '%s\n' "$err" | head -n 1)). It needs glibc 2.35 or newer, GTK 3, WebKitGTK 4.1 and libxdo 3; install the missing one, or LAIR_FLAVOR=headless for the server build."
	fi

	mkdir -p "$DIR"
	# Copy beside the target, then rename over it: rename is atomic on one
	# filesystem, so a lair that is running keeps its old file and nothing ever
	# sees half a binary.
	staged="$DIR/.lair.new.$$"
	cp "$tmp/x/lair" "$staged"
	chmod 755 "$staged"
	mv -f "$staged" "$DIR/lair"
	staged=""
	# Which Linux x86_64 build this is, for the next upgrade to keep.
	if [ "$os" = Linux ] && [ -n "$FLAVOR" ]; then
		printf '%s\n' "$FLAVOR" >"$DIR/.lair-flavor"
	fi
	say "Installed $DIR/lair"

	case ":$PATH:" in
	*":$DIR:"*) ;;
	*)
		say ""
		say "$DIR is not on your PATH. Add it with:"
		case ${SHELL##*/} in
		zsh) say "  echo 'export PATH=\"$DIR:\$PATH\"' >> ~/.zshrc" ;;
		bash)
			profile="$HOME/.bashrc"
			[ "$os" = Darwin ] && profile="$HOME/.bash_profile"
			say "  echo 'export PATH=\"$DIR:\$PATH\"' >> $profile"
			;;
		fish) say "  fish_add_path $DIR" ;;
		*) say "  echo 'export PATH=\"$DIR:\$PATH\"' >> ~/.profile" ;;
		esac
		say "then open a new terminal."
		;;
	esac

	if [ "$asset" = lair-linux-x86_64-desktop.tar.gz ]; then
		say ""
		say "\`lair login-item on\` starts LAIR at login."
	fi
	say ""
	say "Run \`lair\` to sign in or create an account."
}

main "$@"
