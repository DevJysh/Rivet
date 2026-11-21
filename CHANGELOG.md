# Changelog

All notable changes to Rivet are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `--verbose` (`-v`) for `install` and `uninstall`. It prints each step to stderr.
- `rivet list --ids`, which prints one identifier per line for scripts and shell completion.
- Shell completion for bash, zsh, and fish. `make install` puts the files in the standard locations.
- A GitHub Actions workflow that builds and tests on Ubuntu, and builds the Arch Linux package with `makepkg`.
- This changelog, a contributing guide, and a security policy.
- `make distclean`, which also removes test caches and built packages. Installed files and the registry are never touched.

### Changed

- The Goose build in the README and the PKGBUILD passes `-w`, which hides about 40 compiler warnings from Goose's own source. Rivet's build prints none either way.

## [0.1.0] - 2026-11-11

### Added

- Install AppImages into the application menu, with the icon extracted when one is present.
- `uninstall`, `list`, `info`, and `register` (double-click install).
- Version checks on install: a newer or older version of an installed app asks for confirmation, and the same version is refused.
- `--dry-run` for install, and a `--wait` flag for double-click installs.
- An Uninstall action in each menu entry.
- `rivet-gui`, a small graphical front end.
- Copies use the kernel's fast paths (reflink, then `copy_file_range`).
