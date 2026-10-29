#!/bin/sh
# Copies a generated level set (a `LevelForge generate --out DIR` folder) into a debug build of the
# app as a level set of its own, next to the shipped levels; RotateRings/Levels is only read. Levels
# the set lacks (1-10) come from the shipped files. In the app: Settings → Level Browser → the
# level set menu (top right) switches between the shipped levels and the installed sets.
#
#   LevelForge/install-set.sh DIR [NAME] [--device NAME|UDID]
#
# NAME defaults to DIR's folder name. Without --device the set goes to the booted simulator, which
# needs a debug build of the app installed once. With --device it goes to a phone running a debug
# build from Xcode (`xcrun devicectl list devices` lists them).
set -eu

bundle_id=Lumi.RotateRings
root=$(cd "$(dirname "$0")/.." && pwd)
dir= name= device=
while [ $# -gt 0 ]; do
    case $1 in
        --device) device=$2; shift 2 ;;
        *) if [ -z "$dir" ]; then dir=$1; else name=$1; fi; shift ;;
    esac
done
[ -n "$dir" ] && [ -f "$dir/levels-report.json" ] || { echo "usage: $0 DIR [NAME] [--device NAME|UDID] (DIR needs levels-report.json)" >&2; exit 1; }
name=${name:-$(basename "$dir")}

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp "$root"/RotateRings/Levels/level[0-9]*.json "$staging"/
cp "$dir"/level[0-9]*.json "$dir"/levels-report.json "$staging"/
[ -f "$dir/levels-candidates.json" ] && cp "$dir/levels-candidates.json" "$staging"/

if [ -z "$device" ]; then
    container=$(xcrun simctl get_app_container booted "$bundle_id" data)
    target="$container/Documents/LevelSets/$name"
    rm -rf "$target"
    mkdir -p "$target"
    cp "$staging"/* "$target"/
    # The app reads the list of sets when the Level Browser opens; a fresh launch also drops any
    # cached files of a set with the same name.
    xcrun simctl terminate booted "$bundle_id" 2>/dev/null || true
    echo "Installed $(ls "$target" | grep -c '^level[0-9]') levels as \"$name\" on the booted simulator."
else
    xcrun devicectl device copy to --device "$device" --domain-type appDataContainer --domain-identifier "$bundle_id" \
        --source "$staging" --destination "Documents/LevelSets/$name" --remove-existing-content true
    echo "Installed \"$name\" on $device. Quit and reopen the app before switching to it."
fi
