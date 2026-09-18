#!/usr/bin/env bash

set -Eeuo pipefail

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

package="${1:-}"
[ -n "$package" ] || die "usage: verify-package.sh PACKAGE.txz"
[ -f "$package" ] || die "package does not exist: $package"

command -v tar >/dev/null 2>&1 || die "required command is missing: tar"
command -v xz >/dev/null 2>&1 || die "required command is missing: xz"

entries="$(tar -tJf "$package")" || die "cannot read package: $package"
[ -n "$entries" ] || die "package is empty: $package"

require_entry() {
    local expected="$1"
    printf '%s\n' "$entries" | grep -Fqx "$expected" || die "package is missing: $expected"
}

while IFS= read -r entry; do
    case "$entry" in
        /*|../*|*/../*|*/..)
            die "unsafe archive path: $entry"
            ;;
        ./lib|./lib/*|./lib64|./lib64/*|./usr/lib|./usr/lib/*|./usr/lib64|./usr/lib64/*)
            die "package contains a top-level system library path: $entry"
            ;;
        ./etc/ssh|./etc/ssh/*|./usr/sbin/sshd)
            die "package contains an SSH path: $entry"
            ;;
    esac
done <<< "$entries"

while read -r _mode owner_or_links owner_or_uid group_or_gid _rest; do
    if [[ "$owner_or_links" == */* ]]; then
        owner="${owner_or_links%/*}"
        group="${owner_or_links#*/}"
    else
        owner="$owner_or_uid"
        group="$group_or_gid"
    fi

    if [ "$owner" != 0 ] || [ "$group" != 0 ]; then
        die "non-root archive ownership: uid=${owner} gid=${group}"
    fi
done < <(tar --numeric-owner -tvJf "$package")

require_entry ./etc/udev/rules.d/60-openrgb.rules
require_entry ./install/doinst.sh
require_entry ./install/slack-desc
require_entry ./usr/bin/openrgb

printf 'verified %s\n' "$package"
