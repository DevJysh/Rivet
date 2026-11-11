// Rivet: a minimal AppImage installer.
//
//   rivet install ./Krita-5.2.1-x86_64.AppImage
//   rivet uninstall krita
//   rivet list
//
// It copies an AppImage into ~/.local/share/rivet/apps, extracts its icon,
// writes a desktop entry, and records the install in a binary registry so it
// can be listed and removed later. The design is in README.md.
//
// Build (from this directory): goose build rivet.goose
// The C helpers are in rivet_sys.c, which the rivet.build sidecar compiles in.

import os;
import std;

// --- C helpers (rivet_sys.c) -------------------------------------------------
// Goose's os module has no chmod, subprocess or streaming copy, so these are
// bound here. Each takes slices and returns a plain number.

extern fn rv_kind(path: const u8[:]) -> i32;                    // 0 none, 1 file, 2 dir, 3 link, 4 other
extern fn rv_file_size(path: const u8[:]) -> i64;               // -1 if not a regular file
extern fn rv_file_magic(path: const u8[:]) -> i64;              // first four bytes, little-endian; -1 if unreadable
extern fn rv_appimage_type(path: const u8[:]) -> i32;         // 1 or 2 for an AppImage, else 0
extern fn rv_copy_file(src: const u8[:], dst: const u8[:]) -> i32;  // 0 ok, -1 failed, -2 same file
extern fn rv_chmod(path: const u8[:], mode: i32) -> i32;
extern fn rv_run(dir: const u8[:], prog: const u8[:], a1: const u8[:], a2: const u8[:]) -> i32;
extern fn rv_remove_tree(path: const u8[:]) -> i32;

// --- constants ----------------------------------------------------------------

let ELF_MAGIC = 0x464c457f;     // "\x7fELF"
let PNG_MAGIC = 0x474e5089;     // "\x89PNG"
let EXEC_MODE = 493;            // 0755
let MAX_ID = 32;                // the registry's id field is u8[..32]
let SCALABLE_SCORE = 100000;    // an SVG in "scalable" beats any pixel size
let MIB = 1048576;

// --- data ---------------------------------------------------------------------

// One installed AppImage. Variable-size fields are stored inline, so the whole
// registry is one flat array of these, written and read as bytes.
struct AppEntry {
    id:           u8[..32],
    name:         u8[varint],
    version:      u8[varint],
    path:         u8[varint],
    desktop:      u8[varint],
    icon:         u8[varint],
    size_bytes:   i64,
    installed_at: i64,
}

// The best icon found in an AppImage. score 0 means none was found. path is
// relative to the AppImage's root; size is the theme's size directory.
struct Pick {
    score: i64,
    size:  u8[..16],
    ext:   u8[..4],
    path:  u8[..256],
}

// $XDG_DATA_HOME, or ~/.local/share. Set once by main before any command runs.
var data_home: u8[>..];

// --- small helpers ------------------------------------------------------------

fn fail(msg: u8[:]) {
    write_stderr(str("rivet: ", msg, "\n"));
}

fn set_data_home() -> bool {
    var xdg: u8[>..] = [];
    if env("XDG_DATA_HOME", xdg) && xdg.len > 0 && xdg[0] == '/' {
        data_home = copy(xdg);
        return true;
    }
    var home: u8[>..] = [];
    if env("HOME", home) && home.len > 0 && home[0] == '/' {
        data_home = str(home, "/.local/share");
        return true;
    }
    return false;
}

fn under_data(rel: u8[:]) -> u8[>..] {
    return str(data_home, "/", rel);
}

// mkdir -p for an absolute path.
fn make_dirs(path: u8[:]) {
    for i in 1..path.len {
        if path[i] == '/' { make_dir(path[..i]); }
    }
    make_dir(path);
}

fn basename(p: u8[:]) -> u8[:] {
    let k = rfind(p, "/");
    if k < 0 { return p; }
    return p[k + 1..];
}

fn drop_suffix(s: u8[:], suffix: u8[:]) -> u8[:] {
    if ends_with(s, suffix) { return s[..s.len - suffix.len]; }
    return s;
}

// "Krita" from "krita": the first letter upper-cased, the rest as written.
fn push_display(out: u8[>..]&, raw: u8[:]) {
    if raw.len == 0 { return; }
    if raw[0] >= 'a' && raw[0] <= 'z' {
        out.push(raw[0] - 32);
    } else {
        out.push(raw[0]);
    }
    format(out, raw[1..]);
}

// An app's id: lowercase letters, digits and . _ + -. Any other byte, a space
// included, becomes '-'. The id names the registry entry and the desktop file.
fn make_id(name: u8[:], out: u8[>..]&) {
    for c in name {
        if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '+' || c == '-' {
            out.push(c);
        } else if c >= 'A' && c <= 'Z' {
            out.push(c + 32);
        } else {
            out.push('-');
        }
    }
}

// "Krita-5.2.1-x86_64.AppImage" gives the name "Krita" and version "5.2.1".
// The version starts at the first '-' followed by a digit. Returns false if
// no name is left.
fn split_file_name(base: u8[:], name: u8[>..]&, version: u8[>..]&) -> bool {
    var stem: u8[:] = drop_suffix(base, ".AppImage");
    stem = drop_suffix(stem, ".appimage");
    for arch in ["-x86_64", "-x86-64", "-amd64", "-aarch64", "-arm64", "-i686", "-i386", "-armhf"] {
        stem = drop_suffix(stem, arch);
    }
    var k = 0;
    for j in 1..stem.len {
        if k == 0 && stem[j - 1] == '-' && ascii::is_digit(stem[j]) { k = j; }
    }
    if k == 0 {
        push_display(name, stem);
        return name.len > 0;
    }
    if k < 2 { return false; }
    push_display(name, stem[..k - 1]);
    format(version, stem[k..]);
    return true;
}

// Text for a menu entry: "Krita 5.2.1", or "Krita" when there is no version.
fn label(name: u8[:], version: u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    format(out, name);
    if version.len > 0 { format(out, " ", version); }
    return out;
}

// A path inside an Exec= line: double-quoted, with the characters that are
// special there escaped. '%' is doubled, since it starts a field code.
fn quote_exec(out: u8[>..]&, path: u8[:]) {
    out.push('"');
    for c in path {
        if c == '"' || c == '`' || c == '$' || c == '\\' { out.push('\\'); }
        if c == '%' { out.push('%'); }
        out.push(c);
    }
    out.push('"');
}

fn desktop_text(out: u8[>..]&, name: u8[:], exec: u8[:], icon: u8[:]) {
    format(out, "[Desktop Entry]\nType=Application\nName=", name, "\nExec=");
    quote_exec(out, exec);
    format(out, " %U\nTerminal=false\nCategories=Utility;\n");
    if icon.len > 0 { format(out, "Icon=", icon, "\n"); }
}

// Left-justified in a column of the given width, with a space after it.
fn column(s: u8[:], width: i64) -> u8[>..] {
    var out: u8[>..] = [];
    format(out, s);
    while out.len < width { out.push(' '); }
    out.push(' ');
    return out;
}

fn size_text(bytes: i64) -> u8[>..] {
    var out: u8[>..] = [];
    if bytes >= MIB {
        format(out, bytes / MIB, " MB");
    } else {
        format(out, bytes / 1024, " KB");
    }
    return out;
}

// --- registry -----------------------------------------------------------------

fn registry_path() -> u8[>..] { return under_data("rivet/registry.bin"); }
fn apps_path() -> u8[>..] { return under_data("rivet/apps"); }
fn desktop_path() -> u8[>..] { return under_data("applications"); }

// The registry as it is on disk. A missing file is an empty registry. A damaged
// one is ignored, with a warning, and the next save replaces it.
fn load_registry() -> AppEntry[>..] {
    var apps: AppEntry[>..] = [];
    let path = registry_path();
    if !file_exists(path) { return apps; }
    var image: u8[>..] = [];
    if !read_file(path, image) {
        fail("cannot read the registry");
        return apps;
    }
    if image.len == 0 { return apps; }
    var loaded, ok = from_bytes<AppEntry[>..]>(image);
    if !ok {
        fail("the registry is damaged and was ignored");
        return apps;
    }
    return loaded;
}

fn save_registry(apps: AppEntry[>..]&) -> bool {
    make_dirs(under_data("rivet"));
    return write_file_atomic(registry_path(), to_bytes(apps));
}

// Asks the desktop database to pick up the entries. Optional: a missing tool
// is not an error.
fn refresh_desktop_db() {
    rv_run("", "update-desktop-database", desktop_path(), "");
}

// --- icons --------------------------------------------------------------------

// The score of an icon theme size directory: "scalable" is best; "NxN" scores N;
// anything else scores 0 and is skipped.
fn size_score(size: u8[:]) -> i64 {
    if size == "scalable" { return SCALABLE_SCORE; }
    let x = find(size, "x");
    if x <= 0 || x + 1 >= size.len { return 0; }
    let n, ok = parse_int(size[..x]);
    if !ok || n <= 0 || n > 1024 { return 0; }
    if size[x + 1..] != size[..x] { return 0; }
    return n;
}

// Looks through usr/share/icons/<theme>/<size>/apps for the best icon. Links
// are never followed, so an icon that is a link is skipped.
fn find_icon(root: u8[:]) -> Pick {
    var best = Pick { score: 0, size: "", ext: "", path: "" };
    let icons = str(root, "/usr/share/icons");
    if rv_kind(icons) != 2 { return best; }
    var themes: u8[>..] = [];
    list_dir(icons, themes);
    for theme in split(themes, '\n') {
        if theme.len == 0 { continue; }
        let theme_dir = str(icons, "/", theme);
        if rv_kind(theme_dir) != 2 { continue; }
        var sizes: u8[>..] = [];
        list_dir(theme_dir, sizes);
        for size in split(sizes, '\n') {
            if size.len == 0 { continue; }
            let score = size_score(size);
            if score == 0 { continue; }
            let apps = str(theme_dir, "/", size, "/apps");
            if rv_kind(apps) != 2 { continue; }
            var files: u8[>..] = [];
            list_dir(apps, files);
            for file in split(files, '\n') {
                if file.len == 0 { continue; }
                let svg = ends_with(file, ".svg");
                if !svg && !ends_with(file, ".png") { continue; }
                let rel = str("usr/share/icons/", theme, "/", size, "/apps/", file);
                if score > best.score && rel.len <= 256 && size.len <= 16 {
                    best = Pick {
                        score: score,
                        size:  size,
                        ext:   if svg { "svg" } else { "png" },
                        path:  rel,
                    };
                }
            }
        }
    }
    return best;
}

// Clears an extraction folder, and the tmp folder above it once it is empty.
fn drop_work(work: u8[:]) {
    rv_remove_tree(work);
    delete_dir(under_data("rivet/tmp"));
}

// Pulls the icon out of an installed AppImage into the icon theme and returns
// its path, or an empty string when there is none. An icon is optional, so
// nothing here is an error.
fn extract_icon(app: u8[:], id: u8[:]) -> u8[>..] {
    let work = under_data(str("rivet/tmp/", id));
    drop_work(work);
    make_dirs(work);

    // The AppImage extracts its own filesystem into ./squashfs-root, so this
    // needs no FUSE and no squashfs library.
    rv_run(work, app, "--appimage-extract", "usr/share/icons");
    var root = str(work, "/squashfs-root");
    var pick = find_icon(root);

    if pick.score == 0 {
        // Some AppImages only carry a .DirIcon at the top: a PNG is good enough.
        let fallback = str(work, "/fallback");
        make_dirs(fallback);
        rv_run(fallback, app, "--appimage-extract", ".DirIcon");
        root = str(fallback, "/squashfs-root");
        let dir_icon = str(root, "/.DirIcon");
        if rv_kind(dir_icon) == 1 && rv_file_magic(dir_icon) == PNG_MAGIC {
            pick = Pick { score: 1, size: "256x256", ext: "png", path: ".DirIcon" };
        }
    }

    if pick.score == 0 {
        drop_work(work);
        return [];
    }

    let src = str(root, "/", pick.path[..]);
    if rv_kind(src) != 1 {
        drop_work(work);
        return [];
    }
    let icon_dir = under_data(str("icons/hicolor/", pick.size[..], "/apps"));
    make_dirs(icon_dir);
    let dest = str(icon_dir, "/rivet-", id, ".", pick.ext[..]);
    if rv_copy_file(src, dest) != 0 {
        drop_work(work);
        return [];
    }
    drop_work(work);
    return dest;
}

// --- commands -----------------------------------------------------------------

fn install(src: u8[:]) -> i32 {
    if !file_exists(src) {
        fail(str("no such file: ", src));
        return 1;
    }
    // The file is run to extract its icon, so it must carry the AppImage
    // signature first: an ELF header alone is not enough.
    if rv_file_magic(src) != ELF_MAGIC || rv_appimage_type(src) == 0 {
        fail(str(src, " is not an AppImage"));
        return 1;
    }

    let base = basename(src);
    var name:    u8[>..] = [];
    var version: u8[>..] = [];
    if !split_file_name(base, name, version) {
        fail("cannot read an app name from the file name");
        return 1;
    }
    var id: u8[>..] = [];
    make_id(name, id);
    if id.len == 0 || id.len > MAX_ID {
        fail("the app name is empty or too long");
        return 1;
    }

    var apps = load_registry();
    for e in apps {
        if e.id[..] == id[..] {
            fail(str(label(e.name, e.version), " is installed; this file is ",
                     label(name, version), ". Run `rivet uninstall ", id, "` first to replace it."));
            return 1;
        }
    }

    // Copy the AppImage into Rivet's own folder, executable.
    make_dirs(apps_path());
    var fname: u8[>..] = [];
    format(fname, base);
    to_lower(fname);
    let dest = str(apps_path(), "/", fname);
    let rc = rv_copy_file(src, dest);
    if rc == -2 {
        fail("that file is already the installed copy");
        return 1;
    }
    if rc != 0 {
        fail(str("could not copy ", src, " to ", dest));
        return 1;
    }
    rv_chmod(dest, EXEC_MODE);

    // Everything else is optional: a missing icon just means the default one.
    let icon = extract_icon(dest, id);
    let desk_dir = desktop_path();
    make_dirs(desk_dir);
    let desk = str(desk_dir, "/rivet-", id, ".desktop");
    var text: u8[>..] = [];
    desktop_text(text, name, dest, icon);
    if !write_file(desk, text) {
        delete_file(dest);
        fail("could not write the desktop entry");
        return 1;
    }

    apps.push(AppEntry {
        id:           id,
        name:         copy(name),
        version:      copy(version),
        path:         copy(dest),
        desktop:      copy(desk),
        icon:         copy(icon),
        size_bytes:   rv_file_size(dest),
        installed_at: time_ns() / 1000000000,
    });
    if !save_registry(apps) {
        delete_file(desk);
        delete_file(dest);
        if icon.len > 0 { delete_file(icon); }
        fail("could not write the registry; nothing was installed");
        return 1;
    }

    refresh_desktop_db();
    print("installed ", label(name, version));
    return 0;
}

fn uninstall(name: u8[:]) -> i32 {
    var id: u8[>..] = [];
    make_id(name, id);

    var apps = load_registry();
    var kept: AppEntry[>..] = [];
    var found = false;
    var shown:     u8[>..] = [];
    var gone_path: u8[>..] = [];
    var gone_desk: u8[>..] = [];
    var gone_icon: u8[>..] = [];
    for e in apps {
        if e.id[..] == id[..] {
            found = true;
            shown = label(e.name, e.version);
            format(gone_path, e.path);
            format(gone_desk, e.desktop);
            format(gone_icon, e.icon);
        } else {
            kept.push(copy(e));
        }
    }
    if !found {
        fail(str("'", id, "' is not installed (see `rivet list`)"));
        return 1;
    }

    // The registry goes first: if that write fails, nothing has been removed.
    if !save_registry(kept) {
        fail("could not update the registry; nothing was removed");
        return 1;
    }
    delete_file(gone_path);
    delete_file(gone_desk);
    if gone_icon.len > 0 { delete_file(gone_icon); }
    refresh_desktop_db();
    print("removed ", shown);
    return 0;
}

fn list_apps() -> i32 {
    let apps = load_registry();
    if apps.len == 0 {
        print("no AppImages installed");
        return 0;
    }
    print(" Installed AppImages (", apps.len, ")");
    print();
    print(" ", column("Name", 14), column("Version", 11), "Size");
    var rule: u8[>..] = [];
    for i in 31 { rule.append("─"); }
    print(" ", rule);
    for e in apps {
        print(" ", column(e.name, 14), column(e.version, 11), size_text(e.size_bytes));
    }
    return 0;
}

fn usage() {
    print("usage:");
    print("  rivet install <file.AppImage>   add an AppImage to your application menu");
    print("  rivet uninstall <name>          remove an installed AppImage");
    print("  rivet list                      show installed AppImages");
    print("  rivet --version                 print the version");
}

fn main() {
    let a = args();
    if !set_data_home() {
        fail("neither XDG_DATA_HOME nor HOME is set to an absolute path");
        exit(1);
    }

    var status: i32 = 2;
    if a.len == 3 && a[1] == "install" {
        status = install(a[2]);
    } else if a.len == 3 && a[1] == "uninstall" {
        status = uninstall(a[2]);
    } else if a.len == 2 && a[1] == "list" {
        status = list_apps();
    } else if a.len == 2 && (a[1] == "--version" || a[1] == "version") {
        print("rivet 0.1.0");
        status = 0;
    } else if a.len == 2 && (a[1] == "help" || a[1] == "-h" || a[1] == "--help") {
        usage();
        status = 0;
    } else {
        fail("unknown command, or the wrong arguments");
        usage();
    }
    exit(status);
}
