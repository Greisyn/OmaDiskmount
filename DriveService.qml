pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Drives.js" as Drives

// Disk Mounter service. Polls `lsblk -J`, dispatches `udisksctl`
// mount/unmount/unlock/lock/power-off, and mounts one corner-anchored
// DriveWindow per screen. No sudo: udisks2 polkit handles auth.
Item {
  id: root
  property var shell: null
  property var manifest: null
  readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : "local.disk-mounter"

  DriveConfig { id: config }

  // ---------------- drive state ----------------
  property var drives: []
  property string lastError: ""
  property string busyPath: ""
  property string busyLabel: ""

  readonly property var visibleDrives: drives.filter(function(d) {
    return !d.isOsDisk && (config.showSystem || !d.isSystem);
  })
  readonly property int mountedCount: drives.filter(function(d) { return !d.isOsDisk && !d.isSystem && d.mounted; }).length
  readonly property int lockedCount: drives.filter(function(d) { return !d.isOsDisk && d.locked; }).length
  readonly property string summary: {
    var usable = drives.filter(function(d) { return !d.isOsDisk; });
    if (!usable.length) return "No removable drives";
    var bits = [];
    if (root.lockedCount) bits.push(root.lockedCount + " locked");
    var un = usable.filter(function(d) { return !d.locked && !d.mounted && !d.isSystem; }).length;
    if (un) bits.push(un + " unmounted");
    if (root.mountedCount) bits.push(root.mountedCount + " mounted");
    return bits.length ? bits.join(" · ") : String(usable.length) + " drives";
  }

  function pollNow() {
    if (poller.running || opRunner.running) return;
    poller.command = Drives.lsblkArgs();
    poller.running = true;
  }

  Process {
    id: poller
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = Drives.parseLsblk(this.text);
        root.drives = list;
      }
    }
  }

  Timer {
    id: pollTimer
    interval: config.loaded ? config.pollMs : 2500
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.pollNow()
  }

  // ---------------- operation runner (serial queue) ----------------
  property var opQueue: []

  function enqueue(label, path, cmd, after) {
    opQueue.push({ label: label, path: path, cmd: cmd, after: after || null });
    pumpQueue();
  }

  function pumpQueue() {
    if (opRunner.running || !opQueue.length) return;
    var op = opQueue[0];
    root.busyPath = op.path;
    root.busyLabel = op.label;
    root.lastError = "";
    opRunner.command = op.cmd;
    opRunner.running = true;
  }

  Process {
    id: opRunner
    stderr: StdioCollector { id: opStderr; waitForEnd: true }
    stdout: StdioCollector { id: opStdout; waitForEnd: true }
    onExited: function(code) {
      var op = root.opQueue.shift();
      if (code !== 0 && op) {
        var msg = (opStderr.text || opStdout.text || ("exit " + code)).trim().split("\n").pop();
        root.lastError = op.label + " failed: " + msg;
      }
      root.busyPath = "";
      root.busyLabel = "";
      // Auto-lock: after unmounting a LUKS cleartext device, lock backing.
      // Auto-open: after mounting (e.g. post-unlock), reveal in file manager.
      if (code === 0 && op && op.after) {
        if (op.after.lock) {
          root.opQueue.unshift({
            label: "Lock " + op.after.lock, path: op.after.lock,
            cmd: Drives.lockArgs(op.after.lock), after: null
          });
        }
        // Chained safe power-off: unmount finished, now power the disk off.
        // (Lock is skipped here — the device is about to vanish anyway.)
        if (op.after.powerOff) {
          root.opQueue.unshift({
            label: "Power off " + op.after.powerOff, path: op.after.powerOff,
            cmd: Drives.powerOffArgs(op.after.powerOff), after: null
          });
        }
        if (op.after.open) {
          var mp = Drives.parseMountPoint(opStdout.text);
          if (mp !== "") root.openAt(mp);
        }
      }
      root.pumpQueue();
      if (!root.opQueue.length) Qt.callLater(root.pollNow);
    }
  }

  function mountAt(d) {
    // Unlocked LUKS rows must mount the cleartext device, not the
    // crypto container (udisks rejects the container as not mountable).
    var target = (d.isCrypto && d.cleartextPath) ? d.cleartextPath : d.path;
    enqueue("Mount " + target, d.path, Drives.mountArgs(target), null);
  }

  function unmountAt(d) {
    // d may be a LUKS row (act on cleartext) or a plain row.
    var target = (d.isCrypto && d.cleartextPath) ? d.cleartextPath : d.path;
    var after = null;
    if (d.isCrypto && d.cryptoBacking && config.lockOnUnmount) {
      after = { lock: d.cryptoBacking };
    }
    enqueue("Unmount " + target, d.path, Drives.unmountArgs(target), after);
  }

  // Explicit Lock on a mounted LUKS row: always unmount first, then lock
  // regardless of the lockOnUnmount preference (unlike unmountAt, which
  // only auto-locks when the preference is on).
  function unmountAndLock(d) {
    var target = (d.isCrypto && d.cleartextPath) ? d.cleartextPath : d.path;
    var after = (d.isCrypto && d.cryptoBacking) ? { lock: d.cryptoBacking } : null;
    enqueue("Unmount " + target, d.path, Drives.unmountArgs(target), after);
  }

  function lockAt(path) {
    enqueue("Lock " + path, path, Drives.lockArgs(path), null);
  }

  // udisks rejects power-off on mounted drives, so a mounted row is
  // unmounted first and the power-off is chained behind it.
  function powerOff(d) {
    var diskPath = (d && d.diskPath) ? d.diskPath : String(d && d.path ? d.path : d);
    if (d && d.mounted) {
      var target = (d.isCrypto && d.cleartextPath) ? d.cleartextPath : d.path;
      enqueue("Unmount " + target, d.path, Drives.unmountArgs(target),
              { powerOff: diskPath });
    } else {
      enqueue("Power off " + diskPath, diskPath, Drives.powerOffArgs(diskPath), null);
    }
  }

  function openAt(mp) {
    if (!mp) return;
    Quickshell.execDetached(["xdg-open", String(mp)]);
  }

  // ---------------- LUKS unlock via key-file ----------------
  // Passphrase never touches argv/ps: it is written to a 700-dir key
  // file, consumed with --key-file, then shredded.
  property string pendingUnlockPath: ""

  FileView {
    id: keyFile
    path: config.keyFilePath
    atomicWrites: false
    printErrors: false
  }

  function unlock(path, passphrase) {
    if (!passphrase) {
      root.lastError = "Passphrase cannot be empty.";
      return;
    }
    root.pendingUnlockPath = path;
    root.busyPath = path;
    root.busyLabel = "Unlock " + path;
    root.lastError = "";
    keyFile.setText(String(passphrase));
    unlockDelay.restart();
  }

  Timer {
    id: unlockDelay
    interval: 150
    repeat: false
    onTriggered: {
      unlockRunner.command = Drives.unlockArgs(root.pendingUnlockPath, config.keyFilePath);
      unlockRunner.running = true;
    }
  }

  Process {
    id: unlockRunner
    stderr: StdioCollector { id: unlockStderr; waitForEnd: true }
    stdout: StdioCollector { id: unlockStdout; waitForEnd: true }
    onExited: function(code) {
      var p = root.pendingUnlockPath;
      // Scrub the key file immediately: overwrite then remove.
      keyFile.setText("000000000000000000000000000000000000000000000000");
      scrubRunner.running = true;
      var chained = false;
      if (code !== 0) {
        var msg = (unlockStderr.text || unlockStdout.text || ("exit " + code)).trim().split("\n").pop();
        root.lastError = "Unlock failed: " + msg;
      } else {
        // Unlocked: auto-mount the cleartext device, then reveal it in
        // the file manager. The mount op carries after.open for that.
        root.lastError = "";
        var dev = Drives.parseUnlockedDevice(unlockStdout.text);
        if (dev !== "") {
          root.opQueue.push({
            label: "Mount " + dev, path: p,
            cmd: Drives.mountArgs(dev), after: { open: true }
          });
          root.pumpQueue();
          chained = true;
        }
      }
      root.pendingUnlockPath = "";
      if (!chained) {
        root.busyPath = "";
        root.busyLabel = "";
        Qt.callLater(root.pollNow);
      }
    }
  }

  Process {
    id: scrubRunner
    command: ["shred", "-u", "-n", "1", config.keyFilePath]
    onExited: function(code) {
      if (code !== 0) keyFile.setText("");
    }
  }

  // ---------------- per-screen corner windows ----------------
  Variants {
    id: windows
    model: Quickshell.screens
    DriveWindow {
      required property var modelData
      screen: modelData
      service: root
      cfg: config
    }
  }

  IpcHandler {
    target: root.pluginId
    function show(): string { for (var w of windows.instances) w.reveal(); return "shown"; }
    function hide(): string { for (var w of windows.instances) w.collapse(); return "hidden"; }
    function toggle(): string {
      var any = false;
      for (var w of windows.instances) if (w.expanded) { any = true; break; }
      if (any) { for (var w2 of windows.instances) w2.collapse(); return "hidden"; }
      for (var w3 of windows.instances) w3.reveal();
      return "shown";
    }
    function status(): string {
      var states = [];
      for (var w of windows.instances) states.push(!!w.expanded);
      return JSON.stringify({ summary: root.summary, drives: root.visibleDrives.length, busy: root.busyLabel, lastError: root.lastError, expanded: states });
    }
  }
}
