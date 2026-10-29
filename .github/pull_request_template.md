## What this changes



## Checklist

- [ ] `swift test` passes, and `UNBLOCK_EJECT_DISK_TESTS=1 swift test --filter DiskImageTests` if it touches finding or ejecting disks
- [ ] No new permissions, entitlements or dependencies (or explained above)
- [ ] Nothing is quit without a click, and nothing is ever force-quit, killed or force-ejected
- [ ] No file is opened, written or deleted
- [ ] Changes to `EjectCore` come with tests, using made-up disks and apps
