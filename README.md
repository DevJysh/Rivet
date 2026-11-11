# Rivet

Rivet is a small command-line installer for [AppImage](https://appimage.org) applications. It adds an AppImage to your application menu, extracts its icon, and keeps a record of what it installed, so you can list and remove it cleanly later.

Rivet is written in [Goose](https://github.com/aardappel/goose). It builds to a single binary of about 100 KB that depends only on the C library. It makes no network connections, runs no background services, and never needs root.

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [How installation works](#how-installation-works)
- [Files and locations](#files-and-locations)
- [Security](#security)
- [Limitations](#limitations)
- [Roadmap](#roadmap)
- [Development](#development)
- [License](#license)

## Features

- **Install** an AppImage into your desktop with one command. Rivet copies it to a managed location, makes it executable, and creates a menu entry.
- **Icon extraction.** Rivet takes the icon from inside the AppImage. It prefers an SVG, otherwise the largest PNG, and falls back to the top-level `.DirIcon`. If there is no icon, the application still installs with the default icon.
- **Desktop integration.** Rivet writes a freedesktop `.desktop` entry and refreshes the desktop database when `update-desktop-database` is installed.
- **Registry.** Installed applications are recorded in a binary registry. A damaged registry is detected, reported, and ignored rather than crashing the tool.
- **Clean uninstall.** Rivet removes exactly what it recorded: the AppImage, the desktop entry, the icon, and the registry entry. Nothing else is touched.
- **Duplicate protection.** Installing an application that is already installed is refused, and the message shows the installed version and the one you tried to install.
- **XDG compliant.** Rivet honors `$XDG_DATA_HOME` and falls back to `~/.local/share`.
- **Small and dependency-free.** No daemon, no configuration files, no GUI framework, no network access. The C library is the only runtime dependency.

## Requirements

| Requirement | Notes |
|-------------|-------|
| Linux, x86_64, glibc | Developed and tested on Debian 12. Packaging for Arch Linux is included. |
| [Goose compiler](https://github.com/aardappel/goose) | Version v2026.4 is used. Build it from source with CMake. |
| C compiler | `gcc` or `clang`. Goose uses it to produce the final binary. |
| CMake 3.27 or later | Only needed to build the Goose compiler. |
| `update-desktop-database` | Optional. Provided by `desktop-file-utils`. |
| `fuse2` | Optional. Needed to run AppImages normally. Rivet itself does not need it. |

## Installation

### Arch Linux

The repository includes a `PKGBUILD`. It fetches Goose at its release tag, builds it, builds Rivet, and installs the package.

```bash
sudo pacman -S --needed base-devel cmake git
git clone https://github.com/DevJysh/Rivet
cd Rivet
makepkg -si
```

### Other distributions

Build the Goose compiler, then build and install Rivet:

```bash
git clone --depth 1 --branch v2026.4 https://github.com/aardappel/goose
cmake -S goose -B goose/build -DCMAKE_BUILD_TYPE=Release
cmake --build goose/build --config Release

git clone https://github.com/DevJysh/Rivet
cd Rivet
make GOOSE=../goose/build/goose
sudo make install                # installs to /usr/local/bin/rivet
```

To install to `/usr/bin` instead, run `sudo make install PREFIX=/usr`. To install only for yourself, copy `rivet` into `~/.local/bin`.

If `goose` cannot find its standard library, set `GOOSE_STDLIB=/path/to/goose/stdlib`.

### Running the tests

```bash
make GOOSE=../goose/build/goose test
```

The test suite builds a stand-in AppImage and checks installation, listing, uninstallation, and the edge cases, all inside a temporary home directory.

## Usage

```bash
rivet install ~/Downloads/Krita-5.2.1-x86_64.AppImage
rivet list
rivet uninstall krita
```

| Command | Description |
|---------|-------------|
| `rivet install <file.AppImage>` | Install an AppImage into the application menu |
| `rivet uninstall <name>` | Remove an installed AppImage. The name is case-insensitive, for example `krita` or `Krita`. |
| `rivet list` | Show installed AppImages, with version and size |
| `rivet --version` | Print the version |

Example output of `rivet list`:

```
 Installed AppImages (3)

 Name           Version     Size
 ───────────────────────────────
 Krita          5.2.1       182 MB
 Obsidian       1.5.8       148 MB
 Neovim         0.9.5       12 MB
```

### How names are read

Rivet takes the application name and version from the file name:

| File name | Name | Version | ID |
|-----------|------|---------|----|
| `Krita-5.2.1-x86_64.AppImage` | Krita | 5.2.1 | `krita` |
| `neovim-0.9.5-x86_64.AppImage` | Neovim | 0.9.5 | `neovim` |
| `Hello-World-1.0.AppImage` | Hello-World | 1.0 | `hello-world` |

The version starts at the first `-` followed by a digit, and architecture suffixes such as `-x86_64` or `-aarch64` are removed. The ID is the lowercase name and is what `uninstall` matches against. If a file name has no version, the version column is left blank.

## How installation works

`rivet install` performs these steps in order:

1. **Validate.** The file must have an ELF header and the AppImage signature. Rivet runs the file to extract its icon, so an ordinary program is rejected before it is ever run.
2. **Check for duplicates.** If an application with the same ID is already in the registry, Rivet reports both versions and stops.
3. **Copy.** The file is copied into `~/.local/share/rivet/apps/` with a lowercase name, streamed in pieces, and made executable.
4. **Extract the icon.** Rivet runs the AppImage with `--appimage-extract usr/share/icons` in a temporary folder. The AppImage unpacks its own icon directory there, so neither FUSE nor a squashfs library is needed. The best icon is copied into the icon theme.
5. **Write the desktop entry.** The entry contains the name, a quoted `Exec` path with `%U`, the icon path if one was found, and `Categories=Utility;`.
6. **Register.** The new record is appended to the registry, which is written atomically. If a step fails, the files this install created are removed.
7. **Confirm.** Rivet prints `installed Krita 5.2.1`.

Uninstallation rewrites the registry first, so a failed write removes nothing. It then deletes the recorded files.

## Files and locations

Paths below assume the default `XDG_DATA_HOME`.

```
~/.local/share/rivet/
├── apps/
│   ├── krita-5.2.1-x86_64.appimage
│   └── neovim-0.9.5-x86_64.appimage
└── registry.bin

~/.local/share/applications/
├── rivet-krita.desktop
└── rivet-neovim.desktop

~/.local/share/icons/hicolor/
├── 256x256/apps/rivet-krita.png
└── scalable/apps/rivet-neovim.svg
```

The registry stores its records with Goose's `to_bytes()` and reads them back with `from_bytes()`. Loading checks every tag, length, and link before any data is used. The format is opaque and is read and written only by Rivet. There is no JSON, TOML, or other text parsing.

## Security

- Rivet runs an AppImage once, with `--appimage-extract`, to read its icon. This is the same trust you give the file when you run it, so install only AppImages you trust.
- Only files with a valid AppImage signature are run.
- Rivet never follows symbolic links while it searches for icons or cleans up its temporary folder, so a link inside an AppImage cannot make Rivet read or delete files outside its own folders.
- Rivet only writes inside `$XDG_DATA_HOME` (or `~/.local/share`) and never needs root.

## Limitations

- **Icon extraction depends on `--appimage-extract`.** This works for AppImages built with the type 2 runtime, which is the common format. Other AppImages install without an icon.
- **No update detection.** To replace an installed application with a newer version, run `rivet uninstall` first, then install the new file.
- **Versions come from file names.** A file name that does not follow the `Name-version` pattern produces an entry with no version.
- **Desktop entries are minimal.** Each entry is `Categories=Utility;`. Edit the `.desktop` file in `~/.local/share/applications/` to change it.
- **A damaged registry is ignored.** Rivet warns about it and starts with an empty registry, so the applications that were recorded in it are no longer tracked. Their files remain on disk.
- **Command line only.** There is no graphical interface.

## Roadmap

These features are planned but not yet implemented:

- Install by double-clicking an AppImage, through a MIME type association
- Detect a newer version of an installed application and offer to update it
- Native dialog boxes, using GTK or Tkinter
- Packages for more distributions

## Development

```
.
├── rivet.goose        the program: commands, registry, icons, desktop entries
├── rivet_sys.c        C helpers for operations Goose's standard library lacks
├── rivet.build        sidecar that tells `goose build` to compile rivet_sys.c
├── tests/
│   ├── smoke.sh       end-to-end checks
│   └── fake_appimage.c  stand-in AppImage used by the checks
├── Makefile           build, test, install
└── PKGBUILD           Arch Linux package
```

The Goose code uses no heap allocation and has no garbage collector. The C helpers call `malloc` for temporary path strings. Their functions take slices directly, following Goose's `extern fn` rules.

Rebuild after a change with `make GOOSE=<path-to-goose> && make test`.

## License

Rivet is released under the [MIT License](LICENSE).
