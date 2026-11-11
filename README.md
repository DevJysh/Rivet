<div align="center">

# Rivet

![Rivet banner](docs/banner.png)

**Install AppImages cleanly. Remove them just as cleanly.**

[![License: MIT](https://img.shields.io/badge/license-MIT-2ea44f.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-1f6feb.svg)
![Goose](https://img.shields.io/badge/built%20with-Goose%20v2026.4-0b7285.svg)

</div>

Rivet is a small command-line installer for [AppImage](https://appimage.org) applications. It adds an AppImage to your application menu, extracts its icon, and records the install so it can be listed and removed cleanly.

It is written in [Goose](https://github.com/aardappel/goose) and builds to a single binary whose only runtime dependency is the C library. It makes no network connections, runs no background services, and never needs root.

## Contents

- [Why Rivet](#why-rivet)
- [Quick start](#quick-start)
- [Install](#install)
- [Usage](#usage)
- [Updates](#updates)
- [Graphical front end](#graphical-front-end)
- [Double-click install](#double-click-install)
- [Files](#files)
- [Security](#security)
- [Limitations](#limitations)
- [License](#license)

## Why Rivet

Rivet does one job: it adds an AppImage to your menu, and it removes it cleanly when you ask. Its design takes ideas from [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher), which integrates AppImages into the launcher, lets you update and remove them from there, and opens them with a double-click. Rivet keeps the core of that: integrate, remove, and double-click to install.

Rivet deliberately stays smaller:

- **No daemon and no folder scanning.** Rivet runs when you ask it to, and it touches nothing else.
- **One small binary.** About 118 KB, linked only against the C library.
- **Only what you install.** Rivet records each install in its own registry and removes exactly those files.
- **No update helper, no GUI framework.** Updates are a version comparison you confirm. The optional window is a thin front end over the same command.

## Quick start

```bash
rivet install ~/Downloads/Krita-5.2.1-x86_64.AppImage
rivet list
rivet uninstall krita
```

```
 Installed AppImages (1)

 Name           Version     Size       Installed
 ────────────────────────────────────────────────────
 Krita          5.2.1       182 MB     2026-11-11 05:08 UTC
```

## Install

Requires Linux on x86_64 with glibc, the [Goose compiler](https://github.com/aardappel/goose) v2026.4, and a C compiler.

**Arch Linux**

```bash
git clone https://github.com/DevJysh/Rivet
cd Rivet
makepkg -si
```

**Other distributions**

```bash
git clone --depth 1 --branch v2026.4 https://github.com/aardappel/goose
cmake -S goose -B goose/build -DCMAKE_BUILD_TYPE=Release
cmake --build goose/build

git clone https://github.com/DevJysh/Rivet
cd Rivet
make GOOSE=../goose/build/goose
sudo make install
```

`make install` puts `rivet` and `rivet-gui` in `/usr/local/bin`. Use `PREFIX=/usr` for `/usr/bin`. To run the tests, use `make GOOSE=../goose/build/goose test`.

## Usage

| Command | Description |
|---------|-------------|
| `rivet install <file.AppImage>` | Install an AppImage. An installed application of the same name is updated only after confirmation. |
| `rivet install --dry-run <file.AppImage>` | Show what an install would do, and change nothing. |
| `rivet install --yes <file.AppImage>` | Install and replace an installed version without asking. |
| `rivet uninstall <name>` | Remove an installed application. The name is case-insensitive. |
| `rivet list` | List installed applications with their version, size, and install time. |
| `rivet info <name>` | Show the files, size, install time, and menu entry of one application. |
| `rivet register` | Open AppImage files with Rivet on double-click. |
| `rivet <command> --help` | Show the help for one command. |
| `rivet --version` | Print the version. |

Output is plain text when it is piped or redirected, so scripts can read it. In a terminal, Rivet uses color and shows progress while it works. Set `NO_COLOR` to turn color off.

Rivet reads the name and version from the file name. For example, `Krita-5.2.1-x86_64.AppImage` is Krita 5.2.1, and its ID is `krita`.

## Updates

Installing a file whose application is already installed compares the versions:

- A newer version asks `Update Ferret from 1.0 to 1.1? [y/N]`.
- An older version asks before it replaces the newer one.
- The same version is refused.

Versions compare part by part as numbers, so `10.0` is newer than `9.0`. Without a terminal, for example in a script, Rivet replaces nothing unless you pass `--yes`.

## Launcher actions

Each menu entry has an **Uninstall** action, so you can remove an app from its right-click menu in most desktop environments. The action runs the `rivet` binary that installed the app. If you move Rivet, reinstall the apps to point the actions at the new location.

## Performance

Measured on a 512 MB stand-in AppImage, on Debian 12 with ext4:

| Operation | Time |
|-----------|------|
| Start and print the version | about 3 ms |
| `rivet list` or `rivet info` | a few ms |
| `rivet install` (512 MB) | about 0.4 to 0.5 s, mostly writing to disk |

Rivet copies with the kernel where it can: a reflink on Btrfs, XFS, and bcachefs, and `copy_file_range` elsewhere. On ext4 this cut CPU time for the copy by about 9%. The wall-clock time is limited by the disk.

## Graphical front end

`rivet-gui` is an optional Tkinter window. It lists installed applications with a search box, and shows the details of the selected one. You can install an AppImage (Ctrl+O), uninstall the selected app (Delete), or refresh (F5). Work runs in the background, so the window stays responsive. Installing a newer or older version asks first, as the command line does.

It needs Python 3 with Tkinter, and it runs the `rivet` command for every change. Set `RIVET=/path/to/rivet` to choose a specific binary.

## Double-click install

Run `rivet register` once. It writes `~/.local/share/applications/rivet.desktop` and makes Rivet the default for `application/x-iso9660-appimage`, the MIME type that AppImage files use. Opening an AppImage in your file manager then installs it in a terminal window, which stays open until you press Enter. Run `rivet register` again if you move the `rivet` binary.

## Files

Rivet writes only inside `$XDG_DATA_HOME` (default `~/.local/share`):

```
rivet/apps/                   installed AppImages
rivet/registry.bin            the record of installed applications
applications/rivet-*.desktop  menu entries
icons/hicolor/                extracted icons
```

The registry is a binary file written with Goose's `to_bytes()` and read with `from_bytes()`. A damaged registry is reported and ignored.

## Security

- Installing runs the AppImage once with `--appimage-extract` to read its icon. Install only AppImages you trust.
- Rivet checks the ELF header and the AppImage signature before it runs anything.
- Rivet never follows symbolic links while it searches for icons or cleans up, so a link inside an AppImage cannot make it touch files outside its own folders.

## Limitations

- **Icons** are extracted only from AppImages built with the type 2 runtime, the common format. Other AppImages install with the default icon.
- **Updates** are matched by application name. Rivet does not check for new releases.
- **Versions** come from the file name. A name without a `Name-version` pattern has no version.
- **Desktop entries** are minimal: `Categories=Utility;`. Edit the `.desktop` file to change them.
- **Tested platforms:** Debian 12 only. The Arch `PKGBUILD` has not yet been verified with `makepkg`.
- **Menu actions and the handler use the binary's path.** Reinstall apps, or run `rivet register`, after moving Rivet.
- **Desktop integration** has not been checked in a real desktop. The `register` command was tested with a stub `xdg-mime`, and the graphical front end has not been opened on a display.

## Releases

Each release is a tarball with the stripped `rivet` binary, the `rivet-gui` script, the README, the license, and a `SHA256SUMS` file. Build the same tarball locally with `make dist`.

## License

Rivet is released under the [MIT License](LICENSE).
