#!/bin/sh

set -eu

version_file="${SRCROOT}/Config/Version.xcconfig"
current_version=$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$version_file")

case "$current_version" in
    ''|*[!0-9]*)
        echo "error: Invalid CURRENT_PROJECT_VERSION in $version_file" >&2
        exit 1
        ;;
esac

next_version=$((current_version + 1))
temporary_file="${version_file}.tmp.$$"
trap 'rm -f "$temporary_file"' EXIT

awk -v next_version="$next_version" '
    /^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {
        print "CURRENT_PROJECT_VERSION = " next_version
        updated++
        next
    }
    { print }
    END { if (updated != 1) exit 1 }
' "$version_file" > "$temporary_file"

mv "$temporary_file" "$version_file"
trap - EXIT

echo "Build number incremented: $current_version -> $next_version"
