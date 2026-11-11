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
    case "$out" in *"Krita 5.2.1 is already installed"*) pass "a second install of the same app is refused" ;;
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

# --- updates and replacement -------------------------------------------------

# Ferret and Gadget use names of their own, so the checks above are not affected.
cp "$tmp/fake" "$tmp/Ferret-1.0-x86_64.AppImage"
cp "$tmp/fake" "$tmp/Ferret-1.1-x86_64.AppImage"
cp "$tmp/fake" "$tmp/Gadget-9.0-x86_64.AppImage"
cp "$tmp/fake" "$tmp/Gadget-10.0-x86_64.AppImage"
ferret10="$tmp/Ferret-1.0-x86_64.AppImage"
ferret11="$tmp/Ferret-1.1-x86_64.AppImage"
"$rivet" install "$ferret10" >/dev/null 2>&1 </dev/null

# Without a terminal and without --yes, a different version is not replaced.
out=$("$rivet" install "$ferret11" 2>&1 </dev/null || true)
case "$out" in *"Pass --yes"*) pass "an update needs a yes when there is no terminal" ;;
    *) bad "an update needs a yes when there is no terminal (got: $out)" ;; esac
out=$("$rivet" list 2>&1)
case "$out" in *"Ferret"*"1.0"*) pass "a refused update leaves the old version" ;;
    *) bad "a refused update leaves the old version (got: $out)" ;; esac

# --yes replaces it, and the old files go.
out=$("$rivet" install --yes "$ferret11" 2>&1)
case "$out" in *"updated Ferret 1.0 to Ferret 1.1"*) pass "--yes updates to a newer version" ;;
    *) bad "--yes updates to a newer version (got: $out)" ;; esac
check "the old AppImage is removed after an update" sh -c "! ls '$apps' | grep -qi 'ferret-1\.0'"
check "the new AppImage is installed after an update" test -x "$apps/ferret-1.1-x86_64.appimage"
check "the menu entry is kept after an update" test -f "$XDG_DATA_HOME/applications/rivet-ferret.desktop"

# A version that is the same as the installed one is refused, even with --yes.
out=$("$rivet" install --yes "$ferret11" 2>&1 || true)
case "$out" in *"Ferret 1.1 is already installed"*) pass "the same version is refused even with --yes" ;;
    *) bad "the same version is refused even with --yes (got: $out)" ;; esac

# An older version replaces a newer one only with --yes.
out=$("$rivet" install --yes "$ferret10" 2>&1)
case "$out" in *"replaced Ferret 1.1 with the older Ferret 1.0"*) pass "--yes can replace with an older version" ;;
    *) bad "--yes can replace with an older version (got: $out)" ;; esac

# Versions compare as numbers: 10.0 is newer than 9.0.
"$rivet" install "$tmp/Gadget-9.0-x86_64.AppImage" >/dev/null 2>&1
out=$("$rivet" install --yes "$tmp/Gadget-10.0-x86_64.AppImage" 2>&1)
case "$out" in *"updated Gadget 9.0 to Gadget 10.0"*) pass "versions compare as numbers" ;;
    *) bad "versions compare as numbers (got: $out)" ;; esac

# --- register ----------------------------------------------------------------

# register writes a handler entry for AppImage files. It runs whether or not
# xdg-mime is installed, so the test does not depend on the desktop.
out=$("$rivet" register 2>&1 </dev/null) && rc=0 || rc=$?
check "register exits cleanly" test "$rc" -eq 0
handler="$XDG_DATA_HOME/applications/rivet.desktop"
check "register writes rivet.desktop" test -f "$handler"
check "the handler lists the AppImage MIME type" grep -qF "MimeType=application/x-iso9660-appimage;" "$handler"
check "the handler runs this rivet with the file" grep -qF "Exec=\"$rivet\" install --wait %f" "$handler"

# --- info, dry runs, help, and plain output --------------------------------

# Widget is used only here, so the checks above are not affected.
cp "$tmp/fake" "$tmp/Widget-1.0-x86_64.AppImage"
cp "$tmp/fake" "$tmp/Widget-2.0-x86_64.AppImage"
esc=$(printf '\033')

# A dry run of a new app reports it and installs nothing.
out=$("$rivet" install --dry-run "$tmp/Widget-1.0-x86_64.AppImage" 2>&1)
case "$out" in *"would install Widget 1.0"*) pass "a dry run reports a new install" ;;
    *) bad "a dry run reports a new install (got: $out)" ;; esac
check "a dry run copies nothing" sh -c "! ls '$apps' 2>/dev/null | grep -qi 'widget'"

"$rivet" install "$tmp/Widget-1.0-x86_64.AppImage" >/dev/null 2>&1

# A dry run of a newer version reports the update, and changes nothing.
out=$("$rivet" install --dry-run "$tmp/Widget-2.0-x86_64.AppImage" 2>&1)
case "$out" in *"would update Widget 1.0 to Widget 2.0"*) pass "a dry run reports an update" ;;
    *) bad "a dry run reports an update (got: $out)" ;; esac
check "a dry run leaves the installed version alone" sh -c "ls '$apps' | grep -qi 'widget-1\.0'"

# A dry run of the same version is refused with a failing status.
if out=$("$rivet" install --dry-run "$tmp/Widget-1.0-x86_64.AppImage" 2>&1); then
    bad "a dry run of the same version is refused"
else
    case "$out" in *"Widget 1.0 is already installed"*) pass "a dry run of the same version is refused" ;;
        *) bad "a dry run of the same version is refused (got: $out)" ;; esac
fi

# info shows what was recorded.
out=$("$rivet" info widget 2>&1)
case "$out" in *"Widget 1.0"*"id         widget"*"installed  "*"menu entry"*) pass "info shows the recorded details" ;;
    *) bad "info shows the recorded details (got: $out)" ;; esac
if "$rivet" info nothere >/dev/null 2>&1; then bad "info of an unknown app fails"; else pass "info of an unknown app fails"; fi

# list has an install-time column.
out=$("$rivet" list 2>&1)
case "$out" in *"Installed"*"UTC"*) pass "list shows when each app was installed" ;;
    *) bad "list shows when each app was installed (got: $out)" ;; esac

# Help is available for each command.
out=$("$rivet" install --help 2>&1)
case "$out" in *"--dry-run"*) pass "install --help lists its flags" ;;
    *) bad "install --help lists its flags (got: $out)" ;; esac
out=$("$rivet" info --help 2>&1)
case "$out" in *"rivet info <name>"*) pass "info --help shows its usage" ;;
    *) bad "info --help shows its usage (got: $out)" ;; esac

# Scripts and pipes get plain text, with no escape codes.
out=$("$rivet" list 2>&1)
case "$out" in *"$esc"*) bad "list has no escape codes when piped" ;;
    *) pass "list has no escape codes when piped" ;; esac
out=$("$rivet" install --dry-run "$tmp/Widget-2.0-x86_64.AppImage" 2>&1)
case "$out" in *"$esc"*) bad "a dry run has no escape codes when piped" ;;
    *) pass "a dry run has no escape codes when piped" ;; esac

"$rivet" uninstall widget >/dev/null 2>&1
check "uninstall removes the test app" sh -c "! ls '$apps' | grep -qi 'widget'"

# --- the Uninstall action in the menu ---------------------------------------

# Gizmo is used only here. Its menu entry must offer an Uninstall action that
# removes the app when the launcher runs it.
cp "$tmp/fake" "$tmp/Gizmo-3.0-x86_64.AppImage"
"$rivet" install "$tmp/Gizmo-3.0-x86_64.AppImage" >/dev/null 2>&1
entry="$XDG_DATA_HOME/applications/rivet-gizmo.desktop"
check "the menu entry lists the Uninstall action" grep -q '^Actions=Uninstall;$' "$entry"
check "the menu entry defines the Uninstall action" grep -q '^\[Desktop Action Uninstall\]$' "$entry"
act=$(sed -n '/^\[Desktop Action Uninstall\]/,$p' "$entry" | sed -n 's/^Exec=//p')
case "$act" in *" uninstall gizmo") pass "the action runs rivet uninstall for the app" ;;
    *) bad "the action runs rivet uninstall for the app (got: $act)" ;; esac
sh -c "$act" >/dev/null 2>&1 || true
check "running the Uninstall action removes the app" sh -c "! ls '$apps' | grep -qi 'gizmo'"
check "and its menu entry" test ! -e "$entry"

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
