# Security

Unblock Eject looks at which files other apps have open, and can ask them to quit, so it's built to do exactly that and nothing more, and never on its own.

## Reporting a vulnerability

Please report security problems privately through **Security → Report a vulnerability** on this repository, not in a public issue. You'll get a reply within a few days.

## Why it isn't sandboxed

Most of these apps run in the macOS App Sandbox. This one can't, and it's better to say so plainly than to hide it.

Before writing it, a sandboxed test build was run against a scratch disk image with files held open on it by test processes. Inside the sandbox, asking the kernel for other processes' open files (`proc_listpidspath`, `proc_pidinfo`) was refused with "Operation not permitted", and so was running `/usr/sbin/lsof`, which inherits the sandbox. Asking a test app to quit was refused too. Only ejecting worked. The same build outside the sandbox found every open file and could ask the test app to quit, with no permission prompt.

So Unblock Eject runs outside the sandbox, with as little as possible instead:

- **No entitlements at all.** No network, no Apple Events, no file access exceptions. CI checks every build has none.
- **The hardened runtime,** so other code can't be loaded into it.
- **Nothing for macOS to grant.** No Full Disk Access, Accessibility, Automation, Input Monitoring or Screen Recording.
- **Rules the code follows, checked by CI** rather than the sandbox: no networking code, none of your files is ever opened, written or deleted, no other program is started, nothing is ever forced, and only one file can ask an app to quit and only one can eject.

## What Unblock Eject can access

| | |
|---|---|
| **Which files your processes have open** | It asks the kernel, through libproc, which of your processes have files open on each disk you can eject, and their paths. This is what `lsof` does. The kernel only answers for processes running as you. It reads file *names*, never what's in a file. |
| **Process names** | Each process's name, program path and parent, to name it and find the app or terminal it belongs to. |
| **Which apps are running** | macOS's list of running apps, for their names and icons, and to ask the one you choose to quit. |
| **The mount table and Disk Arbitration** | Which volumes are mounted, and what kind of disk each is on. Nothing is opened on the disks, so a sleeping drive isn't woken. |
| **Ejecting** | Through Disk Arbitration, the same as Finder: unmount, then eject. Only when you click Eject. |
| **App icons** | It asks macOS for each app's icon to show in the menu and window, the way Finder and the Dock do. That's the only thing it reads from an app, and an app on a disk being checked is only read to draw its icon. |
| **Its own settings** | Whether it has run before, and where you left its window, in its preferences file. |

## What it can't or won't do

- **Force anything.** Quit sends the same request as choosing Quit from an app's own menu, which the app can answer by asking to save, or by refusing. It never force-quits, never sends a signal to a process, and never force-ejects. CI checks the code for the usual ways of doing those. Parts of macOS, Finder, shells and commands are never offered to quit at all.
- **Act without you.** It quits only the app you click Quit for, and ejects only the disk you click Eject for. It never quits several at once, and never retries on its own. The one thing it does on its own is turn on Open at Login the first time it runs, like most menu bar apps; it's a switch in the menu.
- **Eject the wrong disk.** A disk plugged in after the list was made can get the same name, like `disk4`. Before unmounting, it checks each volume is still mounted where it was, with the same volume ID, and refuses otherwise.
- **Quit the wrong app.** A process ID can be reused after an app quits, so before quitting, it checks the running app still has the same bundle ID and location as the one listed.
- **Open your files.** It never opens, reads, changes or deletes your files, on your disks or anywhere else. CI checks the code never calls the usual ways of doing that.
- **Use the internet.** It has no networking code, which CI checks on every build.
- **See other users' or the system's processes.** macOS doesn't tell it what they have open. That's why Spotlight's indexer and Time Machine's backup engine can still hold a disk without being listed; the app says so instead of guessing.

Check it yourself on any copy of the app:

```bash
codesign -d --entitlements - "/Applications/Unblock Eject.app"
codesign -dv "/Applications/Unblock Eject.app" 2>&1 | grep flags
```

The first shows no entitlements. The second shows `runtime`, the hardened runtime.

## How it handles things

- **File and process names are treated as untrusted.** A disk can hold a file with any name, including ones built to fool you. Control characters, line breaks and the invisible marks that reorder text right to left are replaced before a name is shown, in the app or in the terminal, so a name can't send your terminal an escape sequence or use a hidden right-to-left mark to make a program's name read like a text file's. Very long names are shortened. The command line tool's JSON is escaped as JSON.
- **Only what really blocks an eject counts.** Files opened only to watch for changes, as the Dock and file watchers do, don't stop an unmount and are left out. Files are matched to a disk by its file system ID rather than path text, so a volume mounted inside another isn't mixed up with it, and something the kernel can't name, like a file deleted while open, is still shown.
- **A failed eject can leave part of a disk unmounted,** as with Finder: on a drive with more than one partition or container, ones nothing was using may be unmounted before macOS refuses the busy one. Unplugging and plugging the drive back in mounts them again. A disk with one volume is left as it was.
- **Parts of macOS are recognized by where they live, not just their name.** Only programs in macOS's protected system folders, which System Integrity Protection guards, are explained as Spotlight, Time Machine and so on. A program elsewhere that calls itself `mdworker` is listed as what it is.
- **Disks are read without waiting on them.** The mount table is read with `MNT_NOWAIT`, so a disk that's stopped answering can't freeze the menu.
- **The command line tool runs as you,** in your terminal. It uses the same code as the app, only lists, and never quits or ejects.
- It has no dependencies. Every line that runs is in this repository. CI checks that too.

## The signature

Releases are signed ad hoc, not with a paid Apple Developer ID, using macOS's default requirement, which names that exact build. Unblock Eject asks macOS for no permissions, so there's nothing for another program to inherit, and nothing to turn on again after an update. A Developer ID signature, which would let macOS confirm the app came from this project without the security warning, is planned.
