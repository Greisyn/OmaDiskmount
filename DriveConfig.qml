import QtQuick
import Quickshell
import Quickshell.Io

// Corner-anchored mounter preferences. DriveService and Panel each
// instantiate this; the JSON file is the single source of truth.
Item {
  id: root
  visible: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || (home + "/.cache")
  readonly property string settingsPath: home + "/.config/omarchy/local.disk-mounter.json"
  readonly property string keyFilePath: runtimeDir + "/omarchy-disk-mounter.key"

  // --- Anchor square (hideable; the bar icon can open the card instead) ---
  property bool showAnchor: true
  // --- Corner snap: any of the four screen corners + margins ---
  property string corner: "bottom-right" // top-left | top-right | bottom-left | bottom-right
  property int cornerMarginX: 24
  property int cornerMarginY: 24
  // --- Shared chrome ---
  property int buttonSize: 52
  property int cardWidth: 390
  property int cardHeight: 470

  // --- Timing & motion ---
  property int openDelay: 300    // hover dwell on the square before reveal (ms)
  property int closeDelay: 900   // leave before collapse (ms)
  property int motionDuration: 240
  property bool reducedMotion: false

  // --- Card chrome ---
  property bool keepOpen: false  // pin: never auto-collapse (persisted)
  property bool showSystem: false
  property bool lockOnUnmount: true // auto-lock LUKS backing after unmount
  property int pollMs: 2500

  property bool loaded: false
  property string lastWritten: ""

  function defaults() {
    return {
      showAnchor: true,
      corner: "bottom-right",
      cornerMarginX: 24, cornerMarginY: 24,
      buttonSize: 52,
      cardWidth: 390, cardHeight: 470,
      openDelay: 300, closeDelay: 900, motionDuration: 240,
      reducedMotion: false, keepOpen: false,
      showSystem: false, lockOnUnmount: true, pollMs: 2500
    };
  }

  function clampNum(v, lo, hi, fallback) {
    var n = Number(v);
    if (!isFinite(n)) n = fallback;
    return Math.round(Math.max(lo, Math.min(hi, n)));
  }

  function load(raw) {
    var d = root.defaults();
    var p = {};
    try { p = JSON.parse(String(raw || "{}")); } catch (e) { p = {}; }
    var corners = ["top-left", "top-right", "bottom-left", "bottom-right"];
    if (corners.indexOf(p.corner) >= 0) d.corner = p.corner;
    if (typeof p.showAnchor === "boolean") d.showAnchor = p.showAnchor;
    d.buttonSize = root.clampNum(p.buttonSize, 40, 96, d.buttonSize);
    d.cornerMarginX = root.clampNum(p.cornerMarginX, 0, 200, d.cornerMarginX);
    d.cornerMarginY = root.clampNum(p.cornerMarginY, 0, 200, d.cornerMarginY);
    d.cardWidth = root.clampNum(p.cardWidth, 300, 640, d.cardWidth);
    d.cardHeight = root.clampNum(p.cardHeight, 320, 900, d.cardHeight);
    d.openDelay = root.clampNum(p.openDelay, 0, 1500, d.openDelay);
    d.closeDelay = root.clampNum(p.closeDelay, 250, 3000, d.closeDelay);
    d.motionDuration = root.clampNum(p.motionDuration, 0, 600, d.motionDuration);
    ["reducedMotion", "keepOpen", "showSystem", "lockOnUnmount"].forEach(function(k) {
      if (typeof p[k] === "boolean") d[k] = p[k];
    });
    d.pollMs = root.clampNum(p.pollMs, 1000, 15000, d.pollMs);

    root.corner = d.corner;
    root.showAnchor = d.showAnchor;
    root.buttonSize = d.buttonSize;
    root.cornerMarginX = d.cornerMarginX; root.cornerMarginY = d.cornerMarginY;
    root.cardWidth = d.cardWidth; root.cardHeight = d.cardHeight;
    root.openDelay = d.openDelay; root.closeDelay = d.closeDelay;
    root.motionDuration = d.motionDuration; root.reducedMotion = d.reducedMotion;
    root.keepOpen = d.keepOpen; root.showSystem = d.showSystem;
    root.lockOnUnmount = d.lockOnUnmount; root.pollMs = d.pollMs;
    root.loaded = true;
  }

  function snapshot() {
    return {
      showAnchor: root.showAnchor,
      corner: root.corner,
      cornerMarginX: root.cornerMarginX, cornerMarginY: root.cornerMarginY,
      buttonSize: root.buttonSize,
      cardWidth: root.cardWidth, cardHeight: root.cardHeight,
      openDelay: root.openDelay, closeDelay: root.closeDelay,
      motionDuration: root.motionDuration, reducedMotion: root.reducedMotion,
      keepOpen: root.keepOpen, showSystem: root.showSystem,
      lockOnUnmount: root.lockOnUnmount, pollMs: root.pollMs
    };
  }

  function save() {
    if (!root.loaded) return;
    var text = JSON.stringify(root.snapshot(), null, 2) + "\n";
    root.lastWritten = text;
    settingsFile.setText(text);
  }

  function set(key, value) {
    if (root[key] === value) return;
    root[key] = value;
    saveTimer.restart();
  }

  function resetAll() {
    var d = root.defaults();
    for (var k in d) root[k] = d[k];
    saveTimer.restart();
  }

  Timer {
    id: saveTimer
    interval: 250
    repeat: false
    onTriggered: root.save()
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: settingsFile.reload()
    onLoaded: {
      if (text() === root.lastWritten && root.loaded) return;
      root.load(text());
    }
    onLoadFailed: root.load("")
  }

  Component.onCompleted: settingsFile.reload()
}
