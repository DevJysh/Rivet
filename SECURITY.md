# Security Policy

## Supported versions

Only the latest release receives security fixes. At the time of writing, that is 0.1.0.

## Reporting a vulnerability

Please report security problems privately, not in a public issue. On the repository's **Security** tab, choose **Report a vulnerability**. If that option is not shown, open an issue that asks for a private contact, and leave out the details.

Please include the Rivet version, your distribution, the steps to reproduce the problem, and what you expected to happen. Reports are read as soon as possible, and a fix is published in a new release with a changelog entry that describes the problem.

## What Rivet does and does not protect against

- **AppImages are programs.** Installing one runs it once with `--appimage-extract` to read its icon, so the AppImage can do anything a program can do. Install only AppImages you trust.
- **Rivet checks the file format, not the publisher.** It checks the ELF header and the AppImage marker. It does not verify cryptographic signatures.
- **Symbolic links are not followed** while Rivet searches for icons or removes files, so a link inside an AppImage cannot make Rivet change files outside its own folders.
- **Rivet runs without root** and does not use the network.
