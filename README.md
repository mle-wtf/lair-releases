# LAIR Minion — releases

Public download host for the [LAIR](https://lair.mle.wtf) Minion, the desktop
half of LAIR. It bridges your local CLI coding agent to the LAIR app on your
phone. The Minion is free.

This repository holds **binaries only**. The source lives in a private repo;
nothing here is built from what you can see in this one.

## Install

macOS, via Homebrew:

    brew tap mle-wtf/lair
    brew install lair-minion

Windows: from the Microsoft Store.

## Why this repo exists

Release assets on a private GitHub repository are auth-gated, so a package
manager cannot fetch them. Homebrew, apt and anything else that downloads a
tarball needs a URL that resolves for an anonymous client, which is what this
repository provides.

## Verification

Every binary here is produced by the source repo's own release recipe, which
refuses to emit an artifact still carrying developer path strings, and proves
the rewrite happened rather than merely reporting a clean scan.
