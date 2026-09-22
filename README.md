# Disk Mounter — floating Omarchy plugin

Corner-anchored floating drive mounter (including LUKS/encrypted volumes),
in the style of `io.github.i12bp8.oshelf` / `local.cliamp-dock`: a small
always-visible square in a screen corner instead of a slim edge handle.

## Install
```bash
omarchy plugin add https://github.com/Greisyn/OmaDiskmount.git --enable
```

- **Mount without sudo**: backend is `udisksctl` (udisks2) — the Omarchy
  polkit agent handles any auth prompts.
- **Plain filesystems**: Mount / Unmount, Open in file manager, Power off
  (removable disks, unmounts first when needed).
- **LUKS volumes**: Unlock… expands an in-card passphrase field. On success
  the cleartext volume is auto-mounted and opened — no extra clicks. After
  unmount, the backing device auto-locks again when `lockOnUnmount` is on.
- **Floating + corner-anchored**: dwell the corner square to reveal, leave
  to collapse, pin open, Esc closes. Corner (top-left/top-right/bottom-left/
  bottom-right) + size in settings.
- **Theme-aware**: all chrome uses `Color.*` / `Style.*` — omarchy themes
  repaint it live.
- **Safe by default**: the OS disk, system mounts (`/`, `/boot`, swap,
  logs), EFI/recovery/restore partitions stay hidden unless `showSystem`
  is enabled. State rescans via `lsblk -J` every `pollMs`.

## Privacy

LUKS passphrases never touch process arguments: they go through a key file
inside the 700-permission runtime dir (`$XDG_RUNTIME_DIR`), consumed via
`udisksctl unlock --key-file`, then overwritten and shredded. No network
calls anywhere — everything stays on your machine.

## Files

- `manifest.json` — service + bar-widget
- `DriveService.qml` — drive state, `lsblk` polling, serial `udisksctl` queue, unlock flow
- `DriveWindow.qml` — per-screen corner square + drive card
- `DriveConfig.qml` — corner/size/motion/mounter prefs → `~/.config/omarchy/local.disk-mounter.json`
- `Drives.js` — `lsblk` parsing, command builders, formatting
- `BarWidget.qml` — bar icon (left = toggle, right = settings)
- `Panel.qml` — settings (square, corner, size, motion, mounter behavior)
- `DriveAction.qml` / `DriveGlyph.qml` — theme-aware pills + line icons

## Note: developing this plugin

Hot-reload (`shell rescanPlugins` / file watcher) reliably picks up
`DriveWindow.qml` / `Panel.qml` / `BarWidget.qml` changes, but does **not**
reliably re-create the long-running `DriveService` — after editing
`DriveService.qml` (or `Drives.js` behavior), run:

```bash
omarchy restart shell
```

## State

- Prefs JSON: `~/.config/omarchy/local.disk-mounter.json`
- Key file (transient, shredded after unlock): `$XDG_RUNTIME_DIR/omarchy-disk-mounter.key`

## Commands

```bash
omarchy-shell local.disk-mounter show
omarchy-shell local.disk-mounter hide
omarchy-shell local.disk-mounter toggle
omarchy-shell local.disk-mounter status
omarchy-shell shell rescanPlugins
omarchy restart shell
```

## Uninstall
```bash
omarchy plugin remove local.disk-mounter
```
