import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar surface: icon ONLY. The mounter floats as a corner square
// (DriveService); this reflects drive state and opens settings.
BarWidget {
  id: root
  moduleName: "local.disk-mounter"

  function injectPanel() {
    var target = panelLoader.item;
    if (!target) return;
    if ("bar" in target) target.bar = root.bar;
    if ("settings" in target) target.settings = root.settings;
    if ("anchorItem" in target) target.anchorItem = button;
    if ("hostWidget" in target) target.hostWidget = root;
  }

  readonly property var driveService: bar && bar.shell ? bar.shell.serviceFor("local.disk-mounter") : null
  readonly property int driveCount: driveService ? driveService.visibleDrives.length : 0
  readonly property int lockedCount: driveService ? driveService.lockedCount : 0
  readonly property string summary: driveService ? String(driveService.summary) : "disk mounter"
  // Bar-themed inks, same convention as first-party widgets:
  // barForeground idle, accent when something needs attention.
  readonly property color idleInk: bar ? bar.barForeground : Color.foreground
  readonly property color glyphInk: root.lockedCount > 0 ? Color.accent : root.idleInk

  // Popout coordinator + KeyboardPanel dismiss path. Dismiss calls
  // owner.close(); without this it would write KeyboardPanel.open
  // directly, killing the open binding (settings opens once, then dead).
  // Always route through the real Panel so state stays in sync.
  function openPanel() { if (panelLoader.item && panelLoader.item.open) panelLoader.item.open(); }
  function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close(); }
  function togglePanel() { if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle(); }
  function closeForPopoutSwitch() { if (panelLoader.item && panelLoader.item.closeForPopoutSwitch) panelLoader.item.closeForPopoutSwitch(); }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: root.injectPanel()
  onSettingsChanged: root.injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel); }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fixedWidth: vertical ? -1 : Style.bar.iconSlot
    text: ""
    labelVisible: false
    hasVisualContent: true
    active: false
    useActiveColor: false
    tooltipText: root.summary + "\nLeft click: toggle drive corner\nRight click: settings"

    // Drawn line glyph (no font-coverage risk), inked with the bar theme.
    DriveGlyph {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      kind: "eject"
      ink: root.glyphInk
    }

    onPressed: function(b) {
      if (!root.bar) return;
      if (b === Qt.RightButton) {
        root.togglePanel();
        return;
      }
      if (b === Qt.LeftButton) {
        Quickshell.execDetached(["omarchy-shell", "local.disk-mounter", "toggle"]);
      }
    }
  }
}
