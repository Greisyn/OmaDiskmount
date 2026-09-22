.pragma library

// Shared drive helpers: lsblk parsing + udisksctl command builders.
// No Qt imports so DriveService and Panel can both use it.

// Columns requested by DriveService poller (must stay in sync).
function lsblkArgs() {
  return ["lsblk", "-J", "-b", "-o",
    "NAME,PATH,FSTYPE,MOUNTPOINT,UUID,SIZE,TYPE,PKNAME,LABEL,VENDOR,MODEL,RM,HOTPLUG,TRAN,PARTLABEL,PARTTYPE"];
}

function mountArgs(path) { return ["udisksctl", "mount", "-b", String(path)]; }
function unmountArgs(path) { return ["udisksctl", "unmount", "-b", String(path)]; }
function lockArgs(path) { return ["udisksctl", "lock", "-b", String(path)]; }
function powerOffArgs(diskPath) { return ["udisksctl", "power-off", "-b", String(diskPath)]; }
function unlockArgs(path, keyFile) {
  return ["udisksctl", "unlock", "-b", String(path), "--key-file", String(keyFile)];
}

var SYSTEM_MOUNTS = ["/", "/boot", "/boot/efi", "/efi", "[SWAP]"];

// GPT partition types that are never user data (lowercase GUIDs).
var SYS_PARTTYPES = [
  "c12a7328-f81f-11d2-ba4b-00a0c93ec93b", // EFI System Partition
  "de94bba4-06d1-4d40-a16a-bfd50179d6f7", // Windows recovery (WinRE)
  "e3c9e316-0b5c-4d88-897d-f488dfb93473", // Microsoft reserved
  "21686148-6449-6e6f-744e-656564454649", // BIOS boot
  "426f6f74-0000-11aa-aa11-00306543ecac"  // Apple recovery / boot
];

// Partition labels that mark vendor recovery / restore / EFI areas.
var SYS_LABELS = ["efi system", "recovery", "restore", "winre",
  "windows re", "oem", "diagnostic", "system reserved"];

// True when a partition node is an EFI / recovery / restore / reserved
// area rather than user-mountable data.
function isAuxPartition(node) {
  var pt = String((node && node.parttype) || "").toLowerCase();
  if (pt && SYS_PARTTYPES.indexOf(pt) >= 0) return true;
  var pl = String((node && (node.partlabel || node.label)) || "").toLowerCase();
  for (var i = 0; i < SYS_LABELS.length; i++) {
    if (pl && pl.indexOf(SYS_LABELS[i]) >= 0) return true;
  }
  return false;
}

function isSystemMount(mp) {
  if (!mp) return false;
  if (SYSTEM_MOUNTS.indexOf(mp) >= 0) return true;
  if (mp === "/var/log" || mp.indexOf("/var/log/") === 0) return true;
  return false;
}

// Plain filesystems we are willing to mount/unmount.
function isMountableFs(fstype) {
  if (!fstype) return false;
  var f = String(fstype).toLowerCase();
  return ["ext4", "ext3", "ext2", "btrfs", "xfs", "vfat", "exfat",
    "ntfs", "ntfs3", "hfsplus", "udf", "f2fs", "iso9660"].indexOf(f) >= 0;
}

function fmtSize(bytes) {
  var n = Number(bytes) || 0;
  if (n <= 0) return "?";
  var units = ["B", "K", "M", "G", "T", "P"];
  var i = 0;
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
  var s = n >= 100 ? Math.round(n).toString()
    : n >= 10 ? n.toFixed(1) : n.toFixed(2);
  return s.replace(/\.0+$|(\.\d)0$/, "$1") + units[i];
}

function deviceLabel(node) {
  var label = String(node.label || "");
  if (label) return label;
  var vendor = String(node.vendor || "").trim();
  var model = String(node.model || "").trim();
  var combined = (vendor + " " + model).trim();
  if (combined) return combined;
  return String(node.name || node.path || "drive");
}

// Walk lsblk JSON into a flat list of actionable drive rows.
// Each row: {path,label,size,fstype,mountpoint,isCrypto,locked,
//   cleartextPath,cryptoBacking,diskPath,removable,tran,mounted,isSystem,
//   isOsDisk,uuid}
function parseLsblk(raw) {
  var out = [];
  var tree = null;
  try { tree = JSON.parse(String(raw || "{}")); } catch (e) { return out; }
  var devs = (tree && tree.blockdevices) || [];
  for (var i = 0; i < devs.length; i++) walk(devs[i], null, out);
  markOsDisks(out);
  // Sort: unlocked-actionable first? Keep stable: locked LUKS, then
  // unmounted, then mounted, each by path.
  out.sort(function(a, b) {
    var ra = a.locked ? 0 : (!a.mounted ? 1 : 2);
    var rb = b.locked ? 0 : (!b.mounted ? 1 : 2);
    if (ra !== rb) return ra - rb;
    return String(a.path) < String(b.path) ? -1 : 1;
  });
  return out;
}

function diskInfo(node, inherited) {
  var diskPath = (inherited && inherited.diskPath) || ("/dev/" + String(node.name || ""));
  var removable = !!(node.rm || node.hotplug);
  if (inherited && inherited.removable) removable = true;
  return {
    diskPath: diskPath,
    removable: removable,
    tran: String(node.tran || ((inherited && inherited.tran) || ""))
  };
}

function walk(node, inherited, out) {
  var type = String(node.type || "");
  var info = diskInfo(node, inherited);
  var kids = node.children || [];

  if (type === "disk") {
    for (var i = 0; i < kids.length; i++) walk(kids[i], info, out);
    return;
  }

  var fstype = String(node.fstype || "");
  var path = String(node.path || ("/dev/" + String(node.name || "")));
  var mp = String(node.mountpoint || "");

  if (fstype === "crypto_LUKS") {
    // Locked when there is no cleartext child; unlocked otherwise.
    var clear = null;
    for (var c = 0; c < kids.length; c++) {
      if (String(kids[c].type || "") === "crypt") { clear = kids[c]; break; }
    }
    if (!clear && kids.length === 1) clear = kids[0]; // be liberal
    if (!clear) {
      out.push({
        path: path, label: deviceLabel(node), size: fmtSize(node.size),
        fstype: "crypto_LUKS", mountpoint: "", isCrypto: true, locked: true,
        cleartextPath: "", cryptoBacking: path,
        diskPath: info.diskPath, removable: info.removable, tran: info.tran,
        mounted: false, isSystem: isAuxPartition(node), uuid: String(node.uuid || "")
      });
    } else {
      var cmp = String(clear.mountpoint || "");
      var cfst = String(clear.fstype || "");
      var cpath = String(clear.path || ("/dev/mapper/" + String(clear.name || "")));
      out.push({
        path: path, label: deviceLabel(node), size: fmtSize(node.size),
        fstype: "crypto_LUKS", mountpoint: cmp, isCrypto: true, locked: false,
        cleartextPath: cpath, cryptoBacking: path,
        diskPath: info.diskPath, removable: info.removable, tran: info.tran,
        mounted: cmp !== "", isSystem: isAuxPartition(node) || isSystemMount(cmp) || !isMountableFs(cfst),
        uuid: String(node.uuid || ""), clearFs: cfst
      });
    }
    // Recurse into non-crypt children just in case (e.g. LVM on LUKS).
    for (var k = 0; k < kids.length; k++) {
      if (kids[k] !== clear) walk(kids[k], info, out);
    }
    return;
  }

  if (type === "crypt") {
    // Standalone mapper (LUKS already unlocked, or LVM). Actionable when
    // it carries a mountable fs.
    if (isMountableFs(fstype)) {
      out.push({
        path: path, label: deviceLabel(node), size: fmtSize(node.size),
        fstype: fstype, mountpoint: mp, isCrypto: true, locked: false,
        cleartextPath: path,
        cryptoBacking: String(node.pkname ? "/dev/" + String(node.pkname) : ""),
        diskPath: info.diskPath, removable: info.removable, tran: info.tran,
        mounted: mp !== "", isSystem: isAuxPartition(node) || isSystemMount(mp),
        uuid: String(node.uuid || "")
      });
    }
    for (var m = 0; m < kids.length; m++) walk(kids[m], info, out);
    return;
  }

  if ((type === "part" || type === "rom") && isMountableFs(fstype)) {
    out.push({
      path: path, label: deviceLabel(node), size: fmtSize(node.size),
      fstype: fstype, mountpoint: mp, isCrypto: false, locked: false,
      cleartextPath: "", cryptoBacking: "",
      diskPath: info.diskPath, removable: info.removable, tran: info.tran,
      mounted: mp !== "", isSystem: isAuxPartition(node) || isSystemMount(mp),
      uuid: String(node.uuid || "")
    });
    for (var p = 0; p < kids.length; p++) walk(kids[p], info, out);
    return;
  }

  // Anything else (empty partitions, loop, zram, etc.): just recurse.
  for (var j = 0; j < kids.length; j++) walk(kids[j], info, out);
}

// The disk(s) hosting the running OS (/, /boot, /boot/efi) are never
// actionable: flag every row on those disks so the UI can hide them
// entirely, not just their system-mounted partitions.
var OS_MOUNTS = ["/", "/boot", "/boot/efi", "/efi", "/var/log"];

function markOsDisks(rows) {
  var osDisks = {};
  for (var i = 0; i < rows.length; i++) {
    if (OS_MOUNTS.indexOf(rows[i].mountpoint) >= 0 && rows[i].diskPath) {
      osDisks[rows[i].diskPath] = true;
    }
  }
  for (var j = 0; j < rows.length; j++) {
    rows[j].isOsDisk = !!osDisks[rows[j].diskPath];
  }
}

function stateText(d) {
  if (!d) return "";
  if (d.isCrypto && d.locked) return "Locked · encrypted";
  if (d.mounted) return "Mounted" + (d.mountpoint ? " · " + d.mountpoint : "");
  return "Unmounted";
}

function detailText(d) {
  var bits = [];
  if (d.fstype) bits.push(d.isCrypto && d.locked ? "LUKS" : String(d.fstype));
  if (d.size) bits.push(String(d.size));
  if (d.tran === "usb" || d.removable) bits.push("USB");
  return bits.join("  ·  ");
}

// udisks prints e.g. "Unlocked /dev/sda1 as /dev/dm-0." — the LAST
// /dev/... token is the cleartext device. Empty string when unparseable.
function parseUnlockedDevice(text) {
  var m = String(text || "").match(/\/dev\/[A-Za-z0-9_.\/-]+/g);
  if (!m || !m.length) return "";
  return m[m.length - 1].replace(/[.,;]+$/, "");
}

// udisks prints e.g. "Mounted /dev/dm-1 at /run/media/user/Label".
// Returns the mountpoint, or "" when unparseable. The trailing sentence
// period udisks appends is stripped (same as parseUnlockedDevice) so the
// path can be passed straight to xdg-open.
function parseMountPoint(text) {
  var m = String(text || "").match(/Mounted\s+\S+\s+at\s+(.+?)\s*$/m);
  return m ? m[1].replace(/[.,;]+$/, "") : "";
}
