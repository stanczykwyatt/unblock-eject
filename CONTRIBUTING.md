# Contributing

Thanks for helping out! Bug reports, ideas and pull requests are all welcome.

## Reporting something it named wrong

If it listed the wrong app, missed something that was using a disk, or explained a process badly, open a [bug report](https://github.com/stanczykwyatt/unblock-eject/issues/new?template=bug.yml) with your macOS version, the kind of disk, and what it showed. Please describe your files rather than pasting their names.

The output of the command line tool helps the most. It lists process names and the files they have open, so look over it first and swap any private file names for something like `photo.jpg`:

```bash
unblock-eject "/Volumes/Your Disk"
```

If it found nothing but the disk still won't eject, this shows what macOS itself has open, which the app can't see. It needs your password:

```bash
sudo lsof +f -- "/Volumes/Your Disk"
```

## Getting started

You need macOS 14 or later and Swift 6 (Xcode 16 or the Command Line Tools).

```bash
swift test                # run the tests
UNBLOCK_EJECT_DISK_TESTS=1 swift test --filter DiskImageTests   # and the ones on a real disk image
scripts/build-app.sh      # build "Unblock Eject.app" and unblock-eject into ./build
open "build/Unblock Eject.app"
```

Finding disks, asking the kernel which files are open, naming what it finds, ejecting, the command line tool and all the wording live in `Sources/EjectCore`, with tests in `Tests/EjectCoreTests`. Most of those use made-up disks and processes. The disk image tests make a scratch disk image, mount it hidden from Finder, hold files open on it from processes the test starts, and check those are found and that ejecting is refused until they stop. They never touch any other disk. A process that should be explained better belongs in `SystemProcess.swift`, with a test; how blockers are grouped is in `Blockers.swift`.

The menu bar app, the menu and the window are in `Sources/UnblockEject`, tested in `Tests/UnblockEjectTests` with made-up disks and apps and windows that are never shown. No test quits a real app or puts anything on screen.

To redraw the art: `swift scripts/make-icon.swift`, `swift scripts/make-art.swift`, and `SCREENSHOT_DIR=docs swift test --filter WindowTests` for the screenshots.

## Ground rules

- **Never force anything.** No force-quit, no signals, no force-eject. Pull requests that add one won't be merged, even behind a setting.
- **Only on a click.** Nothing is quit or ejected unless you clicked that button for that app or disk.
- **Never open a file.** It learns which files are open from the kernel, by name. CI checks nothing opens, writes or deletes one.
- **No network access, ever.** No update checks, analytics or crash reporting that phones home.
- **Least access.** No entitlements and no permission prompts without a very good reason.
- **No new dependencies** without a very good reason. The app has none today, which keeps it easy to audit.
- **Made-up names only** in screenshots, art, tests and bug reports.
- Run `swift test` before opening a pull request, and add tests for changes to `EjectCore`.
- Keep commits small, with a short message saying what changed and why.

## Security issues

Please don't open public issues for vulnerabilities. See [SECURITY.md](SECURITY.md).
