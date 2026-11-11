#!/bin/sh
# Smoke test for rivet. It installs a stand-in AppImage into a scratch home,
# then checks the files, the listing, the duplicate guard, the handling of a
# damaged registry, and uninstall. Usage: tests/smoke.sh [path/to/rivet]
set -eu

here=$(cd "$(dirname "$0")" && pwd)
rivet=$(cd "$(dirname "${1:-./rivet}")" && pwd)/$(basename "${1:-./rivet}")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

# A data home with a space in it, so quoting is exercised too.
export HOME="$tmp/home"
export XDG_DATA_HOME="$tmp/my data"
mkdir -p "$HOME" "$XDG_DATA_HOME"

data="$XDG_DATA_HOME/rivet"
apps="$data/apps"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

check() { # check "description" command...
    desc=$1; shift
    if "$@"; then pass "$desc"; else bad "$desc"; fi
}

cc -O2 -o "$tmp/fake" "$here/fake_appimage.c"
# An AppImage carries "AI" and its type at offset 8 of its ELF header. The
# padding there is unused, and this is where real AppImages put the marker.
printf 'AI\002' | dd of="$tmp/fake" bs=1 seek=8 conv=notrunc 2>/dev/null
cp "$tmp/fake" "$tmp/Krita-5.2.1-x86_64.AppImage"
cp "$tmp/fake" "$tmp/Plain-0.1-x86_64.AppImage"
cp "$tmp/fake" "$tmp/Tool-2.0-x86_64.AppImage"
# The same program without the marker: an ELF file, but not an AppImage.
cc -O2 -o "$tmp/NotAnApp-1.0-x86_64.AppImage" "$here/fake_appimage.c"
printf 'just some text\n' > "$tmp/notes.txt"

# A directory outside the app's tree that a link in the AppImage points at.
trap_dir="$tmp/trap"
mkdir -p "$trap_dir"
printf 'keep me\n' > "$trap_dir/keep.txt"

# --- install -----------------------------------------------------------------

out=$(FAKE_TRAP="$trap_dir" "$rivet" install "$tmp/Krita-5.2.1-x86_64.AppImage")
case "$out" in *"installed Krita 5.2.1"*) pass "install prints the confirmation" ;;
    *) bad "install prints the confirmation (got: $out)" ;; esac

check "AppImage copied, lowercase name" test -f "$apps/krita-5.2.1-x86_64.appimage"
check "AppImage is executable" test -x "$apps/krita-5.2.1-x86_64.appimage"
check "desktop entry written" test -f "$XDG_DATA_HOME/applications/rivet-krita.desktop"
check "SVG icon preferred and installed" \
    test -f "$XDG_DATA_HOME/icons/hicolor/scalable/apps/rivet-krita.svg"
check "desktop entry names the app" \
    grep -q '^Name=Krita$' "$XDG_DATA_HOME/applications/rivet-krita.desktop"
check "Exec quotes a path with a space" \
    grep -q "^Exec=\"$apps/krita-5.2.1-x86_64.appimage\" %U\$" \
    "$XDG_DATA_HOME/applications/rivet-krita.desktop"
check "desktop entry points at the icon" \
    grep -q "^Icon=$XDG_DATA_HOME/icons/hicolor/scalable/apps/rivet-krita.svg\$" \
    "$XDG_DATA_HOME/applications/rivet-krita.desktop"
check "a link inside the AppImage was not followed" test -f "$trap_dir/keep.txt"
check "no temporary extraction left behind" test ! -e "$data/tmp"

# --- list --------------------------------------------------------------------

out=$("$rivet" list)
case "$out" in *"Installed AppImages (1)"*"Krita"*"5.2.1"*) pass "list shows the app" ;;
    *) bad "list shows the app (got: $out)" ;; esac

# --- duplicates --------------------------------------------------------------

if out=$("$rivet" install "$tmp/Krita-5.2.1-x86_64.AppImage" 2>&1); then
    bad "a second install of the same app is refused"
else
    case "$out" in *"is installed; this file is"*) pass "a second install of the same app is refused" ;;
        *) bad "a second install of the same app is refused (got: $out)" ;; esac
fi

# --- rejects non-AppImages ---------------------------------------------------

if "$rivet" install "$tmp/NotAnApp-1.0-x86_64.AppImage" >/dev/null 2>&1; then
    bad "an ELF file without the AppImage marker is rejected"
else
    pass "an ELF file without the AppImage marker is rejected"
fi
check "and it was never run" test ! -e "$data/tmp"

if "$rivet" install "$tmp/notes.txt" >/dev/null 2>&1; then
    bad "a text file is rejected"
else
    pass "a text file is rejected"
fi

# --- an AppImage with no icon still installs ---------------------------------

FAKE_NO_ICONS=1 "$rivet" install "$tmp/Plain-0.1-x86_64.AppImage" >/dev/null
check "an app without an icon installs" test -f "$XDG_DATA_HOME/applications/rivet-plain.desktop"
check "and its desktop entry has no Icon line" \
    sh -c "! grep -q '^Icon=' '$XDG_DATA_HOME/applications/rivet-plain.desktop'"

# --- a top-level .DirIcon is used when the icon theme has nothing -----------

FAKE_DIRICON_ONLY=1 "$rivet" install "$tmp/Tool-2.0-x86_64.AppImage" >/dev/null
check ".DirIcon fallback installs the icon" test -f "$XDG_DATA_HOME/icons/hicolor/256x256/apps/rivet-tool.png"
check ".DirIcon fallback is named in the desktop entry" \
    grep -q "^Icon=$XDG_DATA_HOME/icons/hicolor/256x256/apps/rivet-tool.png\$" \
    "$XDG_DATA_HOME/applications/rivet-tool.desktop"

# --- uninstall ---------------------------------------------------------------

out=$("$rivet" uninstall krita)
case "$out" in *"removed Krita 5.2.1"*) pass "uninstall prints the confirmation" ;;
    *) bad "uninstall prints the confirmation (got: $out)" ;; esac

check "uninstall removes the AppImage" test ! -e "$apps/krita-5.2.1-x86_64.appimage"
check "uninstall removes the desktop entry" test ! -e "$XDG_DATA_HOME/applications/rivet-krita.desktop"
check "uninstall removes the icon" test ! -e "$XDG_DATA_HOME/icons/hicolor/scalable/apps/rivet-krita.svg"
check "uninstall leaves other apps alone" test -f "$apps/plain-0.1-x86_64.appimage"
out=$("$rivet" list)
case "$out" in *"Installed AppImages (2)"*) pass "list shows the remaining apps" ;;
    *) bad "list shows the remaining apps (got: $out)" ;; esac

if out=$("$rivet" uninstall krita 2>&1); then
    bad "uninstalling an app twice fails"
else
    pass "uninstalling an app twice fails"
fi

# --- a damaged registry is ignored, not fatal --------------------------------

printf 'garbage' > "$data/registry.bin"
out=$("$rivet" list 2>&1 || true)
case "$out" in *"damaged"*"no AppImages installed"*) pass "a damaged registry is ignored" ;;
    *) bad "a damaged registry is ignored (got: $out)" ;; esac

echo
if [ "$fails" -eq 0 ]; then
    echo "all checks passed"
else
    echo "$fails check(s) failed"
    exit 1
fi
