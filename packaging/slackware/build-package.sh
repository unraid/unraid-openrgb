#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
readonly REPO_ROOT
readonly PACKAGE_NAME="openrgb"

appimage=""
appdir=""
build_appimage=0
qt="qt6"
openrgb_version="1.0"
architecture="x86_64"
package_release="1"
output_dir="${SCRIPT_DIR}/out"
udev_rules=""
source_date_epoch="${SOURCE_DATE_EPOCH:-0}"
targets=()
source_root="$REPO_ROOT"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: build-package.sh [options]

Build a Slackware package from an OpenRGB AppImage or AppDir.

Options:
  --appimage PATH       Use an existing OpenRGB AppImage.
  --appdir PATH         Use an extracted OpenRGB AppDir.
  --build-appimage      Build OpenRGB with scripts/build-appimage.sh first.
  --qt VALUE            Qt value for --build-appimage: qt5 or qt6. (default: qt6)
  --target VALUE        Optional package tag, for example unraid.
                        Repeat this option to build more than one package.
  --version VALUE       OpenRGB package version. (default: 1.0)
  --architecture VALUE Package architecture. (default: x86_64)
  --release VALUE       Slackware package release. (default: 1)
  --output-dir PATH     Output directory. (default: packaging/slackware/out)
  --udev-rules PATH     Use an existing 60-openrgb.rules file.
  --source-root PATH    OpenRGB source tree to build. (default: repository root)
  -h, --help            Show this help.

The package archive always uses UID 0 and GID 0, regardless of the source
file ownership.
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"
}

absolute_path() {
    local path="$1"
    if [ -d "$path" ]; then
        (cd "$path" && pwd -P)
        return
    fi

    local parent
    parent="$(dirname "$path")"
    [ -d "$parent" ] || die "directory does not exist: $parent"
    printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$(basename "$path")"
}

valid_value() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --appimage)
            [ "$#" -ge 2 ] || die "--appimage needs a path"
            appimage="$2"
            shift 2
            ;;
        --appdir)
            [ "$#" -ge 2 ] || die "--appdir needs a path"
            appdir="$2"
            shift 2
            ;;
        --build-appimage)
            build_appimage=1
            shift
            ;;
        --qt)
            [ "$#" -ge 2 ] || die "--qt needs a value"
            qt="$2"
            shift 2
            ;;
        --target)
            [ "$#" -ge 2 ] || die "--target needs a value"
            targets+=("$2")
            shift 2
            ;;
        --version)
            [ "$#" -ge 2 ] || die "--version needs a value"
            openrgb_version="$2"
            shift 2
            ;;
        --architecture)
            [ "$#" -ge 2 ] || die "--architecture needs a value"
            architecture="$2"
            shift 2
            ;;
        --release)
            [ "$#" -ge 2 ] || die "--release needs a value"
            package_release="$2"
            shift 2
            ;;
        --output-dir)
            [ "$#" -ge 2 ] || die "--output-dir needs a path"
            output_dir="$2"
            shift 2
            ;;
        --udev-rules)
            [ "$#" -ge 2 ] || die "--udev-rules needs a path"
            udev_rules="$2"
            shift 2
            ;;
        --source-root)
            [ "$#" -ge 2 ] || die "--source-root needs a path"
            source_root="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

require_command bash
require_command cp
require_command find
require_command mktemp
require_command tar
require_command xz

valid_value "$openrgb_version" || die "invalid OpenRGB version: $openrgb_version"
valid_value "$architecture" || die "invalid package architecture: $architecture"
valid_value "$package_release" || die "invalid package release: $package_release"
valid_value "$qt" || die "invalid Qt value: $qt"
[[ "$source_date_epoch" =~ ^[0-9]+$ ]] || die "SOURCE_DATE_EPOCH must be an integer"
source_root="$(absolute_path "$source_root")"
[ -d "$source_root" ] || die "OpenRGB source tree does not exist: $source_root"

if [ "$build_appimage" -eq 1 ] && { [ -n "$appimage" ] || [ -n "$appdir" ]; }; then
    die "--build-appimage cannot be combined with --appimage or --appdir"
fi

if [ -n "$appimage" ] && [ -n "$appdir" ]; then
    die "use only one of --appimage and --appdir"
fi

if [ -z "$appimage" ] && [ -z "$appdir" ] && [ "$build_appimage" -eq 0 ]; then
    die "provide --appimage, --appdir, or --build-appimage"
fi

if [ "$build_appimage" -eq 1 ]; then
    [ -f "${source_root}/scripts/build-appimage.sh" ] || die "OpenRGB AppImage build script is missing"
    case "$qt" in
        qt5|qt6) ;;
        *) die "--qt must be qt5 or qt6" ;;
    esac
    (
        cd "$source_root"
        env -u SOURCE_DATE_EPOCH ./scripts/build-appimage.sh "$qt"
    )
    appimage="${source_root}/OpenRGB-${architecture}.AppImage"
fi

if [ -n "$appimage" ]; then
    appimage="$(absolute_path "$appimage")"
    [ -f "$appimage" ] || die "AppImage does not exist: $appimage"
    [ -x "$appimage" ] || die "AppImage is not executable: $appimage"
fi

if [ -n "$appdir" ]; then
    appdir="$(absolute_path "$appdir")"
    [ -d "$appdir" ] || die "AppDir does not exist: $appdir"
fi

if [ -n "$udev_rules" ]; then
    udev_rules="$(absolute_path "$udev_rules")"
    [ -s "$udev_rules" ] || die "udev rules file is empty or missing: $udev_rules"
fi

if [ "${#targets[@]}" -eq 0 ]; then
    targets=("")
fi

for target in "${targets[@]}"; do
    [ -z "$target" ] || valid_value "$target" || die "invalid package target: $target"
done

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/openrgb-slackware.XXXXXX")"
cleanup() {
    rm -rf "$temp_dir"
}
trap cleanup EXIT

source_appdir="$appdir"
if [ -n "$appimage" ]; then
    extract_dir="${temp_dir}/appimage"
    mkdir -p "$extract_dir"
    (
        cd "$extract_dir"
        APPIMAGE_EXTRACT_AND_RUN=1 "$appimage" --appimage-extract >/dev/null
    )
    source_appdir="${extract_dir}/squashfs-root"
fi

[ -x "${source_appdir}/AppRun" ] || die "AppDir is missing an executable AppRun: $source_appdir"
[ -x "${source_appdir}/usr/bin/OpenRGB" ] || die "AppDir is missing usr/bin/OpenRGB: $source_appdir"

stage="${temp_dir}/stage"
mkdir -p \
    "${stage}/etc/udev/rules.d" \
    "${stage}/install" \
    "${stage}/usr/bin" \
    "${stage}/usr/libexec/openrgb" \
    "${stage}/usr/share/doc/openrgb-1.0"

cp -a "$source_appdir" "${stage}/usr/libexec/openrgb/OpenRGB.AppDir"
cp "${SCRIPT_DIR}/doinst.sh" "${stage}/install/doinst.sh"
cp "${SCRIPT_DIR}/slack-desc" "${stage}/install/slack-desc"
cp "${SCRIPT_DIR}/README.openrgb" "${stage}/usr/share/doc/openrgb-1.0/README.openrgb"
chmod 0755 "${stage}/install/doinst.sh"

cat > "${stage}/usr/bin/openrgb" <<'EOF'
#!/bin/sh
set -eu

appdir=/usr/libexec/openrgb/OpenRGB.AppDir

if [ ! -x "$appdir/AppRun" ]; then
    echo "OpenRGB runtime is not installed: $appdir" >&2
    exit 127
fi

exec "$appdir/AppRun" "$@"
EOF
chmod 0755 "${stage}/usr/bin/openrgb"

if [ -n "$udev_rules" ]; then
    cp "$udev_rules" "${stage}/etc/udev/rules.d/60-openrgb.rules"
else
    "${source_appdir}/AppRun" --print-udev-rules \
        > "${stage}/etc/udev/rules.d/60-openrgb.rules"
fi

[ -s "${stage}/etc/udev/rules.d/60-openrgb.rules" ] || die "OpenRGB generated an empty udev rules file"

mkdir -p "$output_dir"
output_dir="$(absolute_path "$output_dir")"

tar_flavor="$(tar --version 2>&1 | sed -n '1p')"
tar_args=(-c -J)
if [[ "$tar_flavor" == *"GNU tar"* ]]; then
    tar_args+=(--sort=name "--mtime=@${source_date_epoch}" --owner=0 --group=0 --numeric-owner)
else
    tar_args+=(--uid 0 --gid 0 --uname root --gname root)
fi

for target in "${targets[@]}"; do
    package_tag="${package_release}_unraid"
    [ -z "$target" ] || package_tag+="$target"
    package_path="${output_dir}/${PACKAGE_NAME}-${openrgb_version}-${architecture}-${package_tag}.txz"

    tar "${tar_args[@]}" -f "$package_path" -C "$stage" .
    "${SCRIPT_DIR}/verify-package.sh" "$package_path"
    printf 'built %s\n' "$package_path"
done
