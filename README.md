# Rivet

**A minimal AppImage installer written in Goose.**

One binary. It depends only on libc. No runtime. No heap in the Goose code. It installs AppImages into your desktop and nothing more.

---

## Problem

AppImages are portable. That's their strength and their weakness. You download one, make it executable, and run it. But it doesn't appear in your application menu. It has no icon in your launcher. When you download a newer version, the old one sits in your Downloads folder forever. There is no way to see what you have installed or remove it cleanly.

Existing solutions (AppImageLauncher, Gear Lever) are written in C++/Qt or Python/GTK. They pull in large dependency trees, run background services, and try to be app stores. Most users just want the AppImage to show up in their menu and be removable later.

---

## Solution

Rivet does exactly three things:

1. **Install** an AppImage into your desktop
2. **Uninstall** an AppImage from your desktop
3. **List** what is currently installed

That's it. No store. No daemon. No update checker. No GUI framework. No network calls.

---

## Build and install

You need two things: the [Goose compiler](https://github.com/aardappel/goose) and a C compiler. On Arch:

```bash
sudo pacman -S --needed base-devel cmake git

# Build the Goose compiler (it is not in the Arch repositories)
git clone --depth 1 --branch v2026.4 https://github.com/aardappel/goose
cmake -S goose -B goose/build -DCMAKE_BUILD_TYPE=Release
cmake --build goose/build --config Release

# Build and test Rivet
git clone https://github.com/DevJysh/Rivet
cd Rivet
make GOOSE=../goose/build/goose test

# Install
sudo make install                 # /usr/local/bin/rivet
sudo make install PREFIX=/usr     # or /usr/bin/rivet
```

`make test` runs `tests/smoke.sh`. It builds a stand-in AppImage and checks install, list, uninstall, and the edge cases, all inside a scratch home directory.

On Arch, the `PKGBUILD` in this repository builds Goose and Rivet and installs a package with `makepkg -si`. To run AppImages normally you still need `fuse2`. Rivet does not need it, because it extracts icons with the AppImage's own `--appimage-extract` option.

If `goose` reports that it cannot find its standard library, point it at the `stdlib` directory of the Goose source tree with `GOOSE_STDLIB=/path/to/goose/stdlib`.

---

## How It Works

### Install

```
rivet install ./Krita-5.2.1-x86_64.AppImage
```

Rivet performs these steps in order:

**Step 1 — Validate.** Read the first four bytes of the file. They must be `0x7F 'E' 'L' 'F'`. The file must also carry the AppImage marker: the bytes `'A' 'I'` and a type byte (1 or 2) at offset 8. Rivet runs the file to extract its icon, so an ELF file that is not an AppImage is rejected before anything runs.

**Step 2 — Check for duplicates.** Load the registry. Scan for an entry whose `id` matches the app name extracted from the filename. If found, print the installed version and the new version, then exit. The user can uninstall the old one first if they want to replace it.

The name comes from the filename. `Krita-5.2.1-x86_64.AppImage` gives the name `Krita`, version `5.2.1`, and id `krita`. The version starts at the first `-` followed by a digit. The architecture suffix (`-x86_64`, `-aarch64`, and similar) is dropped. The id is the lowercase name, with any character outside `a-z 0-9 . _ + -` turned into `-`.

**Step 3 — Copy.** Copy the AppImage file to `~/.local/share/rivet/apps/`, with the lowercase file name, and set the executable bit with `chmod 755`. The copy is streamed in pieces, so a large AppImage never has to fit in memory.

**Step 4 — Extract icon.** Run the AppImage with `--appimage-extract usr/share/icons` in a temporary folder. The AppImage unpacks its own filesystem there, so no FUSE and no squashfs library are needed. Pick the best icon in `usr/share/icons/<theme>/<size>/apps/`: an SVG in `scalable` beats any PNG, and a larger size beats a smaller one. Copy it to `~/.local/share/icons/hicolor/<size>/apps/rivet-<id>.<png|svg>`. If the theme has no icon, try the top-level `.DirIcon` (PNG only). If there is no icon, skip this step silently. The app will still work; it will just use the system's default application icon. Links inside the AppImage are never followed.

**Step 5 — Create desktop entry.** Write a `.desktop` file to `~/.local/share/applications/rivet-<id>.desktop` containing the app name, the quoted exec path with `%U`, the icon path if there is one, and `Categories=Utility;`. Run `update-desktop-database` if it is installed.

**Step 6 — Register.** Append an `AppEntry` record to the in-memory registry. Write the registry to disk as a binary blob using Goose's `to_bytes()`. The write is atomic: a new file replaces the old one in one rename. If the write fails, the copied files are removed.

**Step 7 — Confirm.** Print one line: `installed Krita 5.2.1`.

### Uninstall

```
rivet uninstall krita
```

Rivet loads the registry, finds the matching entry, and deletes exactly four files:

1. The AppImage in `~/.local/share/rivet/apps/`
2. The `.desktop` file in `~/.local/share/applications/`
3. The icon in `~/.local/share/icons/`
4. The registry entry (rewrites the registry without it)

The registry is rewritten first. If that fails, nothing is removed. Nothing else is touched. User configuration files, application data, and home directory contents are left alone. Rivet only removes what Rivet created.

### List

```
rivet list
```

Loads the registry and prints a table:

```
 Installed AppImages (3)

 Name           Version     Size
 ───────────────────────────────
 Krita          5.2.1       182 MB
 Obsidian       1.5.8       148 MB
 Neovim         0.9.5       12 MB
```

If the registry is empty, prints `no AppImages installed`.

---

## Data Model

The entire state of Rivet is one array of fixed-layout records:

```goose
struct AppEntry {
    id: u8[..32]          // lowercase app name, e.g. "krita"
    name: u8[varint]      // display name, e.g. "Krita"
    version: u8[varint]   // e.g. "5.2.1"
    path: u8[varint]      // absolute path to .AppImage
    desktop: u8[varint]   // absolute path to .desktop file
    icon: u8[varint]      // absolute path to icon file, or empty
    size_bytes: i64       // file size at install time
    installed_at: i64     // unix timestamp
}
```

The registry is stored as a binary file at `~/.local/share/rivet/registry.bin`. It is written with `to_bytes()` and read with `from_bytes()`. The binary format uses Goose's relative references, making the data position-independent. Loading verifies every tag, length, and link before the bytes become a value. A corrupt or tampered file causes `from_bytes()` to return `false`. Rivet then prints a warning, treats the registry as empty, and the next save replaces it.

There is no JSON. There is no TOML. There is no text parsing. The registry is an opaque binary that only Rivet reads and writes.

---

## File Layout

```
~/.local/share/rivet/
├── apps/
│   ├── krita-5.2.1-x86_64.appimage
│   ├── obsidian-1.5.8.appimage
│   └── neovim-0.9.5-x86_64.appimage
└── registry.bin

~/.local/share/applications/
├── rivet-krita.desktop
├── rivet-obsidian.desktop
└── rivet-neovim.desktop

~/.local/share/icons/hicolor/256x256/apps/   (or scalable/apps/ for SVG)
├── rivet-krita.png
├── rivet-obsidian.png
└── rivet-neovim.svg
```

Rivet respects `$XDG_DATA_HOME` if it is an absolute path, falling back to `~/.local/share`. It never writes outside that directory. It never requires root.

---

## Code layout

| File | What it is |
|------|------------|
| `rivet.goose` | The program: commands, registry, icon search, desktop entries |
| `rivet_sys.c` | The C helpers Goose's standard library lacks (see below) |
| `rivet.build` | The sidecar that tells `goose build` to compile `rivet_sys.c` |
| `tests/smoke.sh` | Install, list, uninstall and edge-case checks |
| `tests/fake_appimage.c` | A stand-in AppImage used by the tests |
| `Makefile` | `make`, `make test`, `make install` |
| `PKGBUILD` | Arch package build |

The Goose standard library's `os` module already covers reading and writing files, directories, environment variables, and arguments. The C helpers in `rivet_sys.c` cover what it lacks:

| Helper | Why it is needed |
|--------|------------------|
| `rv_copy_file` | Streams a copy, and refuses to write over the same file or through a link |
| `rv_chmod` | Sets the executable bit |
| `rv_run` | Runs `--appimage-extract` and `update-desktop-database` without a shell, with output discarded |
| `rv_kind`, `rv_file_size`, `rv_file_magic`, `rv_appimage_type` | Look at a file's type, size, and first bytes, without reading the whole file |
| `rv_remove_tree` | Removes the temporary extraction folder; it removes links, never follows them |

---

## What Rivet Does Not Do

| Not This | Why |
|----------|-----|
| Browse or download apps | Not a store |
| Check for updates | Re-install a newer version; Rivet detects the duplicate |
| Run a background daemon | Runs only when invoked |
| Show GUI dialogs | CLI output is sufficient |
| Manage Flatpaks or Snaps | Different tools exist |
| Sandbox applications | Out of scope |
| Auto-update itself | User controls this |
| Phone home | No network calls at all |
| Require root | Everything in `~/.local` |
| Parse JSON or YAML | Binary registry via Goose's memory model |
| Use a GUI framework | No GUI |

---

## Security notes

- Rivet runs the AppImage once, with `--appimage-extract`, to get its icon. That is the same trust you give the AppImage when you run it, so only install AppImages you trust.
- Rivet runs only files that carry the AppImage marker, and only for that one extraction.
- Icons that are links, and links found during cleanup, are never followed.

---

## Design Principles

```
1. One binary, around 100 KB.
2. Three commands: install, uninstall, list.
3. Zero network calls.
4. Zero runtime dependencies beyond libc.
5. Touch only what you create. Remove only what you created.
6. Fail silently on non-critical steps (icon extraction).
7. Fail loudly on critical steps (invalid file, disk full).
8. No configuration files. No flags. No plugins.
```

---

## Summary

Rivet is the smallest possible tool that makes AppImages feel like installed applications. It copies the file, creates a menu entry, extracts an icon, and remembers what it did so it can undo it later. Everything else is someone else's problem.

Built in Goose, its own code has no heap, no allocator, no garbage collector, and no runtime. The registry is a verified binary blob that loads in a single read. The small C helpers use `malloc` for temporary path strings. The program compiles to one C file plus that helper file, and then to one binary.

**Three commands. One binary. Done.**
