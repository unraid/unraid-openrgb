# Slackware package build

This directory builds the OpenRGB AppImage into a Slackware `.txz` package.
The package keeps OpenRGB libraries under `/usr/libexec/openrgb`. It does not
install OpenSSL, SSH, or other system libraries.

The build sets every archive entry to `root:root`. This is required because
Slackware package installation preserves archive ownership. A package built on
macOS must not carry the macOS user's numeric UID or GID into the Unraid host.

## Requirements

Run the package build on a Linux host when an AppImage is not already
available. The package step also runs on macOS when an extracted AppDir is
supplied. The package step needs:

- Bash
- `tar` with ownership override support
- `xz`
- `mktemp`
- `md5sum` or macOS `md5` when generating the Unraid plugin file

## Build the Unraid package

Build the AppImage first, then create the generic Unraid package:

```sh
packaging/slackware/build-package.sh \
  --source-root /path/to/OpenRGB \
  --appimage OpenRGB-x86_64.AppImage
```

The package is written to `packaging/slackware/out/`:

```text
openrgb-1.0-x86_64-1_unraid.txz
```

The package script can also build the AppImage as part of the same command:

```sh
packaging/slackware/build-package.sh \
  --source-root /path/to/OpenRGB \
  --build-appimage
```

OpenRGB is a user-space application. The package does not contain a kernel
module and does not depend on a particular Unraid kernel. Its name therefore
does not include a kernel version.

## Generate the plugin file

Generate the plugin file after the package exists:

```sh
packaging/slackware/build-plugin.sh \
  --version 1.0 \
  --repository OWNER/REPOSITORY \
  --release-tag OPENRGB_RELEASE_TAG \
  --package packaging/slackware/out/openrgb-1.0-x86_64-1_unraid.txz
```

The generated `openrgb.plg` uses the OpenRGB version as its plugin version. It
installs only the OpenRGB package. The package contains the OpenRGB runtime,
wrapper, udev rule, and post-install udev reload. It does not install system
libraries or declare plugin dependencies.

## Verify before installation

Run the verifier for every package:

```sh
packaging/slackware/verify-package.sh \
  packaging/slackware/out/openrgb-1.0-x86_64-1_unraid.txz
```

The verifier fails if an archive entry is not owned by UID 0 and GID 0. It
also fails if the package contains top-level system library directories, SSH
files, absolute paths, or parent-directory traversal.

Install only a package that passes this check.

## GitHub release action

The workflow at `.github/workflows/check-openrgb-updates.yml` checks the
upstream OpenRGB release feed every six hours. It downloads the exact upstream
x86_64 AppImage, creates the generic Unraid package and plugin file, verifies
the package, and uploads the `.txz`, checksum, and `.plg` files to a new GitHub
release.

Run the workflow manually with an existing upstream tag to retry a build or
to package a specific release. The generated plugin uses the stable
`releases/latest/download/openrgb.plg` URL, so future package releases can be
found without changing the installation URL.

For a prerelease tag, the workflow builds from the source tag, applies the
patch in `patches/msi-z890-carbon-wifi.patch`, and marks the GitHub release as
a prerelease. The prerelease plugin points to its exact release asset instead
of the stable update URL.

The workflow skips a release when its package already exists. Run it manually
with `upstream_tag` to build a specific upstream release.
