pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Drives.js" as Drives

// Corner-anchored floating mounter. Unlike oShelf / cliamp-dock (slim edge
// handles), this is a small always-visible square in a screen corner:
// hover-dwell (or tap) reveals the drive card, leaving collapses it.
// Only the square and the open card take input; all other pixels pass
// through to the desktop via the layer-shell input mask.
PanelWindow {
  id: root
  required property var service
  required property var cfg

  readonly property bool showAnchor: cfg.showAnchor
  // Slide direction: from the snapped corner.
  readonly property bool atRight: cfg.corner === "top-right" || cfg.corner === "bottom-right"
  readonly property bool atBottom: cfg.corner === "bottom-left" || cfg.corner === "bottom-right"
  readonly property real topClearance: 44 // keep clear of the top bar
  readonly property bool reducedMotion: cfg.reducedMotion
  property bool expanded: false
  property real openness: expanded ? 1 : 0
  property real dwellProgress: 0
  property string unlockPath: "" // which drive row shows the passphrase field
  property bool passFocused: false // set by the visible passphrase field
  readonly property bool engaged: cornerHover.hovered || cardHover.hovered || cfg.keepOpen || passFocused
  readonly property real btnSize: cfg.buttonSize
  readonly property real btnX: {
    if (!showAnchor) return -1000; // park offscreen so the input mask stays clear
    return atRight ? width - btnSize - cfg.cornerMarginX : cfg.cornerMarginX;
  }
  readonly property real btnY: {
    if (!showAnchor) return -1000;
    return atBottom ? height - btnSize - cfg.cornerMarginY : cfg.cornerMarginY + topClearance;
  }
  readonly property real cardW: Math.min(width - 32, cfg.cardWidth)
  readonly property real cardH: Math.min(height - 32, cfg.cardHeight)
  readonly property real cardX: {
    var x = atRight ? width - cardW - cfg.cornerMarginX : cfg.cornerMarginX;
    return Math.max(16, Math.min(width - cardW - 16, x));
  }
  readonly property real cardY: {
    var y = atBottom ? height - cardH - cfg.cornerMarginY - (showAnchor ? btnSize + 12 : 16)
      : cfg.cornerMarginY + topClearance + (showAnchor ? btnSize + 12 : 16);
    return Math.max(16, Math.min(height - cardH - 16, y));
  }
  readonly property bool attention: service && (service.lockedCount > 0)

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusiveZone: 0
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "disk-mounter"
  WlrLayershell.keyboardFocus: expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  // Only these regions receive input; the rest of the desktop passes through.
  mask: Region {
    item: cornerBtn
    Region {
      x: card.x; y: card.y
      width: root.expanded ? card.width : 0; height: card.height
      radius: card.radius
    }
  }

  Behavior on openness {
    NumberAnimation {
      duration: root.reducedMotion ? 0 : root.expanded ? cfg.motionDuration : Math.round(cfg.motionDuration * 0.75)
      easing.type: Easing.OutCubic
    }
  }

  function reveal() {
    closeTimer.stop(); stopDwell();
    if (expanded) return;
    expanded = true;
    service.pollNow();
    content.forceActiveFocus();
  }
  function collapse() {
    // Explicit dismissal always wins (X, Escape, tap). Auto-collapse is
    // separately gated by `engaged` (hover, keepOpen pin, passphrase focus),
    // so this can never fire while the user is interacting.
    expanded = false;
    unlockPath = ""; // delegates clear their own passphrase field
    content.forceActiveFocus();
    stopDwell();
  }
  function toggle() { expanded ? collapse() : reveal(); }
  function stopDwell() { hoverTimer.stop(); dwell.stop(); dwellProgress = 0; }
  function startDwell() {
    if (expanded || !cornerHover.hovered) return;
    stopDwell();
    hoverTimer.restart(); dwell.restart();
  }

  onEngagedChanged: { if (engaged) closeTimer.stop(); else if (expanded) closeTimer.restart(); }
  onExpandedChanged: { if (!expanded) unlockPath = ""; }

  Timer { id: closeTimer; interval: cfg.closeDelay; onTriggered: { if (!root.engaged) root.collapse(); } }
  Timer { id: hoverTimer; interval: cfg.openDelay; onTriggered: { if (cornerHover.hovered) root.reveal(); } }
  NumberAnimation { id: dwell; target: root; property: "dwellProgress"; from: 0; to: 1; duration: cfg.openDelay }

  // ---- corner square ----
  Rectangle {
    id: cornerBtn
    objectName: "disk-mounter-corner"
    x: root.btnX; y: root.btnY
    width: root.btnSize; height: root.btnSize
    radius: 16
    color: Color.background
    border.width: 1
    border.color: cornerHover.hovered ? Color.accent : Util.alpha(Color.foreground, 0.15)
    opacity: 1 - root.openness * 0.85
    visible: root.showAnchor && opacity > 0
    layer.enabled: visible
    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.35; shadowBlur: 0.5; shadowVerticalOffset: 4 }
    HoverHandler {
      id: cornerHover
      onHoveredChanged: { if (hovered) root.startDwell(); else root.stopDwell(); }
    }
    DriveGlyph {
      anchors.centerIn: parent
      width: 26; height: 26
      kind: root.attention ? "lock" : "drive"
      ink: root.attention ? Color.accent : Color.foreground
    }
    // dwell fill ring (bottom edge of the square)
    Rectangle {
      anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 8 }
      height: 2; radius: 1
      color: "transparent"
      Rectangle {
        width: parent.width * root.dwellProgress; height: parent.height
        radius: 1; color: Color.accent
        visible: root.dwellProgress > 0 && !root.expanded
      }
    }
    // count badge
    Rectangle {
      visible: (service ? service.visibleDrives.length : 0) > 0
      anchors { top: parent.top; right: parent.right; margins: -6 }
      width: 22; height: 22; radius: 11
      color: Color.accent
      Text {
        anchors.centerIn: parent
        text: String(service ? service.visibleDrives.length : 0)
        color: Color.background
        font.family: Style.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
      }
    }
    TapHandler { onTapped: root.toggle() }
  }

  // ---- drive card ----
  Rectangle {
    id: card
    objectName: "disk-mounter-surface"
    x: root.cardX
    y: root.cardY + (root.reducedMotion ? 0 : (1 - root.openness) * (root.atBottom ? 32 : -32))
    width: root.cardW; height: root.cardH
    scale: root.reducedMotion ? 1 : 0.97 + root.openness * 0.03
    opacity: root.openness
    visible: root.openness > 0
    radius: 24
    color: Color.background
    border.width: 1
    border.color: Util.alpha(Color.foreground, 0.15)
    layer.enabled: visible
    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.35; shadowBlur: 0.65; shadowVerticalOffset: 8 }
    HoverHandler { id: cardHover }
    // accent wash
    Rectangle {
      anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
      height: Math.min(parent.height, 160); radius: 23
      gradient: Gradient {
        GradientStop { position: 0; color: Util.alpha(Color.accent, 0.085) }
        GradientStop { position: 1; color: "transparent" }
      }
    }
    FocusScope {
      id: content
      anchors.fill: parent
      Keys.onEscapePressed: {
        if (root.unlockPath !== "") root.unlockPath = "";
        else root.collapse();
      }

      // header icon tile
      Rectangle {
        x: 22; y: 22; width: 40; height: 40; radius: 13
        color: Util.alpha(Color.accent, 0.12)
        border.width: 1; border.color: Util.alpha(Color.accent, 0.17)
        DriveGlyph { anchors.centerIn: parent; width: 23; height: 23; kind: "drive"; ink: Color.accent }
      }
      Text {
        x: 74; y: 20
        text: "Drives"
        color: Color.foreground
        font.family: Style.fontFamily; font.pixelSize: 23; font.weight: Font.DemiBold; font.letterSpacing: -0.6
      }
      Text {
        x: 74; y: 49
        width: parent.width - 210
        text: service ? service.summary : ""
        textFormat: Text.PlainText; elide: Text.ElideRight
        color: Util.alpha(Color.foreground, 0.5)
        font.family: Style.fontFamily; font.pixelSize: 10
      }
      Row {
        anchors.right: parent.right; anchors.rightMargin: 16; y: 23; spacing: 2
        DriveAction { icon: "pin"; hint: cfg.keepOpen ? "Unpin (auto-collapse)" : "Pin open"; selected: cfg.keepOpen; onTriggered: cfg.set("keepOpen", !cfg.keepOpen) }
        DriveAction { icon: "refresh"; hint: "Rescan drives"; enabled: service.busyPath === ""; onTriggered: service.pollNow() }
        DriveAction { icon: "close"; hint: "Close"; onTriggered: root.collapse() }
      }

      Text {
        x: 24; y: 92
        text: "DRIVES  ·  " + (service ? service.visibleDrives.length : 0)
        color: Color.accent
        font.family: Style.fontFamily; font.pixelSize: 10; font.letterSpacing: 1.4
      }

      Flickable {
        id: scroller
        x: 22; y: 114; width: parent.width - 44; height: parent.height - 114 - 62
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: body
          width: scroller.width
          spacing: 10

          Text {
            visible: (service ? service.visibleDrives.length : 0) === 0
            width: parent.width
            text: "No mountable drives found.\nPlug in a USB drive or unlockable LUKS volume."
            wrapMode: Text.Wrap
            color: Util.alpha(Color.foreground, 0.5)
            font.family: Style.fontFamily; font.pixelSize: 12; lineHeight: 1.4
          }

          Repeater {
            model: service ? service.visibleDrives : []
            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property var d: modelData
              readonly property bool busy: service.busyPath !== "" && (service.busyPath === d.path || service.busyPath === d.cleartextPath)
              readonly property bool unlocking: root.unlockPath === d.path
              onUnlockingChanged: { if (!unlocking) unlockField.clear(); }

              width: body.width
              height: inner.implicitHeight + 24
              radius: 14
              color: Util.alpha(Color.foreground, unlocking ? 0.06 : 0.035)
              border.width: 1
              border.color: d.locked ? Util.alpha(Color.accent, 0.35) : Util.alpha(Color.foreground, 0.09)

              Column {
                id: inner
                x: 12; y: 12; width: parent.width - 24
                spacing: 8

                Row {
                  width: parent.width; spacing: 10
                  Rectangle {
                    width: 10; height: 10; radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: d.locked ? Color.accent : d.mounted ? Color.accent : Util.alpha(Color.foreground, 0.3)
                    opacity: d.locked || d.mounted ? 1 : 0.7
                  }
                  Column {
                    width: parent.width - 20 - actions.width - parent.spacing * 2
                    spacing: 1
                    Text {
                      width: parent.width
                      text: d.path + (d.label && d.label !== d.path.split("/").pop() ? "  ·  " + d.label : "")
                      textFormat: Text.PlainText; elide: Text.ElideRight
                      color: Color.foreground
                      font.family: Style.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Text {
                      width: parent.width
                      text: Drives.detailText(d) + "   —   " + Drives.stateText(d)
                      textFormat: Text.PlainText; elide: Text.ElideRight
                      color: Util.alpha(Color.foreground, 0.55)
                      font.family: Style.fontFamily; font.pixelSize: 10
                    }
                  }
                  Row {
                    id: actions
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    // Primary action
                    DriveAction {
                      visible: !d.locked && !d.mounted
                      label: "Mount"
                      hint: "Mount " + ((d.isCrypto && d.cleartextPath) ? d.cleartextPath : d.path)
                      enabled: service.busyPath === ""
                      onTriggered: service.mountAt(d)
                    }
                    DriveAction {
                      visible: d.mounted
                      label: "Unmount"
                      hint: "Unmount " + (d.cleartextPath || d.path)
                      enabled: service.busyPath === ""
                      onTriggered: service.unmountAt(d)
                    }
                    DriveAction {
                      visible: d.locked
                      label: "Unlock…"
                      hint: "Unlock encrypted " + d.path
                      selected: unlocking
                      enabled: service.busyPath === ""
                      onTriggered: {
                        if (unlocking) { root.unlockPath = ""; unlockField.clear(); }
                        else {
                          root.unlockPath = d.path;
                          Qt.callLater(function() { unlockField.forceActiveFocus(); });
                        }
                      }
                    }
                  }
                }

                // secondary row: open / lock / power-off
                Row {
                  width: parent.width; spacing: 2
                  visible: d.mounted || (!d.locked && d.removable) || (d.isCrypto && !d.locked && d.mounted)
                  DriveAction {
                    visible: d.mounted && d.mountpoint
                    label: "Open"
                    hint: "Open " + d.mountpoint + " in file manager"
                    onTriggered: service.openAt(d.mountpoint)
                  }
                  DriveAction {
                    visible: d.isCrypto && !d.locked && d.cryptoBacking
                    label: "Lock"
                    hint: "Lock " + d.cryptoBacking + (d.mounted ? " (unmounts first)" : "")
                    enabled: service.busyPath === ""
                    onTriggered: {
                      if (d.mounted) service.unmountAndLock(d);
                      else service.lockAt(d.cryptoBacking);
                    }
                  }
                  DriveAction {
                    visible: !d.locked && d.removable && d.diskPath
                    icon: "power"
                    label: "Power off"
                    hint: "Safely power off " + d.diskPath
                    enabled: service.busyPath === ""
                    onTriggered: service.powerOff(d)
                  }
                  Text {
                    visible: busy
                    text: (service.busyLabel || "Working…")
                    color: Color.accent
                    font.family: Style.fontFamily; font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                // inline LUKS passphrase
                Column {
                  width: parent.width; spacing: 8
                  visible: unlocking
                  Text {
                    width: parent.width
                    text: "PASSPHRASE FOR " + d.path
                    color: Color.accent
                    font.family: Style.fontFamily; font.pixelSize: 10; font.letterSpacing: 1.2
                  }
                  TextField {
                    id: unlockField
                    width: parent.width; height: 40
                    placeholderText: "Enter LUKS passphrase…"
                    echoMode: TextInput.Password
                    color: Color.foreground
                    placeholderTextColor: Util.alpha(Color.foreground, 0.4)
                    selectionColor: Color.accent
                    selectedTextColor: Color.background
                    font.family: Style.fontFamily; font.pixelSize: 12
                    leftPadding: 12; rightPadding: 12
                    selectByMouse: true
                    enabled: service.busyPath === ""
                    onActiveFocusChanged: root.passFocused = activeFocus
                    onAccepted: {
                      if (text !== "") {
                        service.unlock(d.path, text);
                        clear();
                        content.forceActiveFocus();
                      }
                    }
                    background: Rectangle {
                      radius: 12
                      color: Util.alpha(Color.foreground, 0.035)
                      border.width: 1
                      border.color: unlockField.activeFocus ? Util.alpha(Color.accent, 0.65) : Util.alpha(Color.foreground, 0.09)
                    }
                  }
                  Row {
                    width: parent.width; spacing: 6
                    DriveAction {
                      label: "Unlock"
                      icon: "check"
                      hint: "Unlock " + d.path
                      selected: true
                      enabled: service.busyPath === "" && unlockField.text !== ""
                      onTriggered: {
                        if (unlockField.text !== "") {
                          service.unlock(d.path, unlockField.text);
                          unlockField.clear();
                          content.forceActiveFocus();
                        }
                      }
                    }
                    DriveAction {
                      label: "Cancel"
                      hint: "Cancel unlock"
                      onTriggered: { root.unlockPath = ""; unlockField.clear(); }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // footer
      Rectangle {
        x: 22; y: parent.height - 53; width: parent.width - 44; height: 1
        color: Util.alpha(Color.foreground, 0.075)
      }
      Text {
        x: 24; y: parent.height - 36; width: parent.width - 48
        text: service.lastError !== "" ? service.lastError : (service.busyLabel !== "" ? service.busyLabel + "…" : (root.showAnchor ? "Hover the square to reveal · tap to open" : "Square hidden — open from the bar icon"))
        textFormat: Text.PlainText; elide: Text.ElideRight
        color: service.lastError !== "" ? Color.accent : Util.alpha(Color.foreground, 0.45)
        font.family: Style.fontFamily; font.pixelSize: 10
      }
    }
  }
}
