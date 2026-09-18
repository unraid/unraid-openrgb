# OpenRGB Unraid plugin

This repository contains the Unraid plugin and Slackware packaging files for
OpenRGB. It does not contain a copy or fork of the OpenRGB source code.

## How the package is built

GitHub Actions checks the upstream OpenRGB release feed every six hours. When
it finds a stable release that this repository has not packaged, the workflow:

1. Selects that exact OpenRGB release from Codeberg.
2. Downloads the exact x86_64 AppImage from that upstream release.
3. Creates a generic Unraid Slackware package.
4. Creates a GitHub release with the package, checksum, and `openrgb.plg`.

The package is a user-space application package. It does not contain a kernel
module, so the package name does not include an Unraid kernel version.

## Install on Unraid

Install the latest plugin with:

```text
https://github.com/SimonFair/unraid-openrgb/releases/latest/download/openrgb.plg
```

The plugin installs the OpenRGB runtime, command wrapper, udev rule, and the
post-install udev reload. It does not install SSH files or replace system
libraries.

## Run a build manually

Use the **Check for OpenRGB updates** workflow and enter an upstream tag such
as `release_1.0`. Leave the field empty to use the newest stable release. A
prerelease tag such as `release_candidate_1.0rc3.1` creates a separate GitHub
prerelease and applies the MSI Z890 Carbon WiFi mapping patch.

The workflow is the supported release path. For a local Linux build, provide
an OpenRGB source checkout explicitly:

```sh
packaging/slackware/build-package.sh \
  --source-root /path/to/OpenRGB \
  --build-appimage \
  --version 1.0
```

The package build and verifier documentation is in
`packaging/slackware/README.md`.

## Upstream project

OpenRGB source and release information are available at
[OpenRGB on Codeberg](https://codeberg.org/OpenRGB/OpenRGB).
