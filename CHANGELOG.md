# Changelog

## 0.1.0 (2026-11-13)

First release.

- **See what's using each disk you can eject:** external drives, memory cards and disk images, with every app and process that has a file open on them, its icon and the files.
- **Helpers grouped with their app,** so a renderer or background helper shows up as the app you know.
- **Quit the app that's in the way,** with the same request as its own Quit command, so it can ask to save first. Never forced.
- **Plain explanations** for what can't be quit: a shell in a terminal, a running command, Spotlight, Time Machine, Quick Look, a Photos or Music library, a disk image still open from the disk, a malware check, and Finder.
- **Eject from the menu or the window,** the whole drive at once, the way Finder does, with disk images detached. If it can't, the window says what's still in the way.
- **The `unblock-eject` command line tool** to list the same thing, or JSON, for any disk or path.
- **Open at login**, on by default and easy to turn off.
- No entitlements, no permissions, no internet access and no dependencies. It never opens your files, and never quits or ejects anything without a click.
