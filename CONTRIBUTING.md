# Contributing to Rivet

Thank you for helping with Rivet. It is a small tool, and it stays small on purpose. Changes should keep it that way.

## Design rules

- **No network, no root, no daemon, no configuration files.** Rivet acts only when you run it.
- **Only what Rivet installed.** Uninstall removes exactly the files recorded in the registry.
- **Fast and small.** The binary stays in the 50 to 200 KB range, and libc is its only dependency.

## Building

You need the [Goose compiler](https://github.com/aardappel/goose) v2026.4, a C compiler, and `make`. Build Goose first, then Rivet:

```bash
git clone --depth 1 --branch v2026.4 https://github.com/aardappel/goose
cmake -S goose -B goose/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS=-w -DCMAKE_CXX_FLAGS=-w
cmake --build goose/build
make GOOSE=goose/build/goose
```

## Testing

```bash
make GOOSE=goose/build/goose test
```

This runs the shell smoke tests (`tests/smoke.sh`) and the GUI tests (`tests/gui_test.py`). Both must pass before a change is merged. The CI workflow runs the same tests on Ubuntu and builds the Arch Linux package.

## Style

- Goose code: run `goose format --check rivet.goose` before committing, and fix any reported differences.
- Python: keep `gui/rivet-gui` and `tests/gui_test.py` free of unused names. `pyflakes` is a good check.
- Shell: POSIX `sh` for the tests and scripts.

## Commits and pull requests

- Write a short subject line in the imperative mood, such as "Add a verbose flag to install".
- Keep each commit to one logical change, and explain the reason in the body when it is not obvious.
- Add an entry under `[Unreleased]` in `CHANGELOG.md` for anything a user would notice.
- Open pull requests against `main`. CI must pass before merging.

## Reporting security problems

Please do not open a public issue for a security problem. See [SECURITY.md](SECURITY.md).
