# LAIR releases

Public download host for [LAIR](https://lair.mle.wtf): your own CLI coding
agent, reachable from your phone, end-to-end encrypted. This repository holds
the `lair` binaries for your computer and the scripts that install them. The
source lives in a private repository; nothing here is built from what you can
see in this one.

## Install

macOS and Linux:

    curl -fsSL https://lair.mle.wtf/install.sh | sh

Windows (PowerShell):

    irm https://lair.mle.wtf/install.ps1 | iex

macOS with Homebrew:

    brew install mle-wtf/lair/lair

Then run `lair` to sign in or create an account. No sudo or admin rights are
needed: the scripts install into your user account (`~/.local/bin` on macOS and
Linux) and rerunning one upgrades in place.

## Which file is which

Every release carries these assets:

| file | for |
| --- | --- |
| `lair-macos-universal.tar.gz` | macOS, Apple Silicon and Intel |
| `lair-linux-x86_64-desktop.tar.gz` | Linux x86_64 desktops: tray and chat window. Needs glibc 2.35 or newer (Ubuntu 22.04 on), GTK 3, WebKitGTK 4.1 and libxdo 3 |
| `lair-linux-x86_64.tar.gz` | Linux x86_64 servers: headless, statically linked, no dependencies |
| `lair-linux-arm64.tar.gz` | Linux arm64: headless, statically linked (no arm64 desktop build yet) |
| `lair-windows-x64-setup.exe` | Windows x64 installer, per user |
| `SHA256SUMS` | the SHA-256 of every file above |

`install.sh` picks the Linux desktop build when it finds a graphical session
and GTK 3, and the headless one otherwise; `LAIR_FLAVOR=desktop` or
`LAIR_FLAVOR=headless` overrides it, and an upgrade keeps the one you have.

## Verify a download

The install scripts check every download against `SHA256SUMS` and stop on a
mismatch. `SHA256SUMS` comes from the same release as the files it lists, so
it catches a truncated, corrupted or mixed-up download, not a compromised
release: trust in the release itself rests on GitHub's TLS and the `mle-wtf`
account that publishes it. To check a file by hand, download it and `SHA256SUMS` from the same
release into one directory, then:

    sha256sum --ignore-missing -c SHA256SUMS                     # Linux
    shasum -a 256 --ignore-missing -c SHA256SUMS                 # macOS
    (Get-FileHash lair-windows-x64-setup.exe).Hash               # Windows; compare with its line

Each binary is produced by a release recipe that refuses to emit one still
carrying developer path strings, and proves the rewrite happened rather than
merely reporting a clean scan.
