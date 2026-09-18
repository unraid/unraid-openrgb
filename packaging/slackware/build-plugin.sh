#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR

version=""
repository=""
release_tag=""
package_path=""
plugin_url=""
output_dir="${SCRIPT_DIR}/out"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: build-plugin.sh --version VERSION --repository OWNER/REPOSITORY \
    --release-tag TAG --package PATH [options]

Generate the Unraid OpenRGB plugin file and package checksum.

Options:
  --version VALUE       OpenRGB version written to the plugin file.
  --repository VALUE    GitHub repository that hosts the release assets.
  --release-tag VALUE   GitHub release tag that hosts the package assets.
  --package PATH        Generic Unraid .txz package to install.
  --plugin-url URL      URL used by Unraid for plugin updates.
  --output-dir PATH     Directory for openrgb.plg. (default: packaging/slackware/out)
  -h, --help            Show this help.
EOF
}

valid_value() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            [ "$#" -ge 2 ] || die "--version needs a value"
            version="$2"
            shift 2
            ;;
        --repository)
            [ "$#" -ge 2 ] || die "--repository needs a value"
            repository="$2"
            shift 2
            ;;
        --release-tag)
            [ "$#" -ge 2 ] || die "--release-tag needs a value"
            release_tag="$2"
            shift 2
            ;;
        --package)
            [ "$#" -ge 2 ] || die "--package needs a path"
            package_path="$2"
            shift 2
            ;;
        --plugin-url)
            [ "$#" -ge 2 ] || die "--plugin-url needs a URL"
            plugin_url="$2"
            shift 2
            ;;
        --output-dir)
            [ "$#" -ge 2 ] || die "--output-dir needs a path"
            output_dir="$2"
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

[ -n "$version" ] || die "--version is required"
[ -n "$repository" ] || die "--repository is required"
[ -n "$release_tag" ] || die "--release-tag is required"
[ -n "$package_path" ] || die "--package is required"
valid_value "$version" || die "invalid OpenRGB version: $version"
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || die "invalid GitHub repository: $repository"
[[ "$release_tag" =~ ^[A-Za-z0-9._/-]+$ ]] \
    || die "invalid GitHub release tag: $release_tag"
if [ -n "$plugin_url" ]; then
    [[ "$plugin_url" =~ ^https://[^[:space:]]+$ ]] \
        || die "invalid plugin URL: $plugin_url"
else
    plugin_url="https://github.com/${repository}/releases/latest/download/openrgb.plg"
fi

[ -f "$package_path" ] || die "package does not exist: $package_path"

package_name="$(basename "$package_path")"
expected_package="openrgb-${version}-x86_64-1_unraid.txz"
[ "$package_name" = "$expected_package" ] \
    || die "package name must be ${expected_package}: $package_name"

mkdir -p "$output_dir"
if command -v md5sum >/dev/null 2>&1; then
    package_md5="$(md5sum "$package_path" | awk '{print $1}')"
elif command -v md5 >/dev/null 2>&1; then
    package_md5="$(md5 -q "$package_path")"
else
    die "required command is missing: md5sum or md5"
fi
package_url="https://github.com/${repository}/releases/download/${release_tag}/${package_name}"
plugin_path="${output_dir}/openrgb.plg"
checksum_path="${output_dir}/${package_name}.md5"

cat > "$plugin_path" <<EOF
<?xml version='1.0' standalone='yes'?>
<!DOCTYPE PLUGIN [
<!ENTITY name "openrgb">
<!ENTITY author "OpenRGB">
<!ENTITY version "${version}">
<!ENTITY package "${package_name}">
<!ENTITY packageMD5 "${package_md5}">
<!ENTITY packageURL "${package_url}">
<!ENTITY pluginURL "${plugin_url}">
]>
<PLUGIN name="&name;" author="&author;" version="&version;" pluginURL="&pluginURL;">

<CHANGES>
###&version;
- Install OpenRGB for Unraid.
</CHANGES>

<FILE Run="/bin/bash">
<INLINE>
# Remove old cached OpenRGB packages before the new package is installed.
mkdir -p /boot/config/plugins/&name;
find /boot/config/plugins/&name; -maxdepth 1 -type f -name 'openrgb-*.txz' \\
  ! -name '&package;' -delete

# OpenRGB contains no shared system libraries and no kernel modules.
for installed in /var/log/packages/openrgb-*; do
  [ -f "\$installed" ] || continue
  /sbin/removepkg "\$(basename "\$installed")" >/dev/null 2>&amp;1 || true
done
</INLINE>
</FILE>

<FILE Name="/boot/config/plugins/&name;/&package;" Run="upgradepkg --install-new">
<URL>&packageURL;</URL>
<MD5>&packageMD5;</MD5>
</FILE>

<FILE Run="/bin/bash" Method="remove">
<INLINE>
for installed in /var/log/packages/openrgb-*; do
  [ -f "\$installed" ] || continue
  /sbin/removepkg "\$(basename "\$installed")" >/dev/null 2>&amp;1 || true
done
rm -f /boot/config/plugins/&name;/openrgb-*.txz
rm -f /boot/config/plugins/&name;/openrgb-*.txz.md5
</INLINE>
</FILE>

</PLUGIN>
EOF

printf '%s  %s\n' "$package_md5" "$package_name" > "$checksum_path"
printf 'built %s\n' "$plugin_path"
printf 'built %s\n' "$checksum_path"
