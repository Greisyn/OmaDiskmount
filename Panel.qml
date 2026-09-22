import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Settings panel for Disk Mounter. Opened from the bar icon (right click).
// All colors come from Color.* / Style.* so omarchy themes repaint it live.
Panel {
  id: root
  moduleName: "local.disk-mounter"
  ipcTarget: "local.disk-mounter-panel"
  manageIpc: true

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  DriveConfig { id: config }

  function open() { root.controller.show(); }
  function toggle() { root.opened ? root.close() : root.open(); }

  component RowLabel: Text {
    textFormat: Text.PlainText
    color: root.contentForeground
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.body
  }

  component SectionHeader: Text {
    textFormat: Text.PlainText
    color: Color.accent
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  component SwitchRow: Row {
    property string label: ""
    property bool checked: false
    signal flipped()
    width: parent ? parent.width : 0
    spacing: Style.spacing.lg
    RowLabel { text: parent.label; width: parent.width - sw.width - parent.spacing; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight }
    ToggleSwitch {
      id: sw
      checked: parent.checked
      foreground: root.contentForeground
      accent: Color.accent
      anchors.verticalCenter: parent.verticalCenter
      onToggled: parent.flipped()
    }
  }

  KeyboardPanel {
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    contentWidth: fittedContentWidth(Style.space(440))
    contentHeight: fittedContentHeight(contentColumn.implicitHeight)

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.spacing.xl

        // ---- Corner visibility ----
        SectionHeader { text: "Floating square" }
        Row {
          width: parent.width; spacing: Style.spacing.sm
          WidgetButton { text: "Show"; onPressed: function() { Quickshell.execDetached(["omarchy-shell", "local.disk-mounter", "show"]); } }
          WidgetButton { text: "Hide"; onPressed: function() { Quickshell.execDetached(["omarchy-shell", "local.disk-mounter", "hide"]); } }
          WidgetButton { text: "Toggle"; onPressed: function() { Quickshell.execDetached(["omarchy-shell", "local.disk-mounter", "toggle"]); } }
        }
        SwitchRow { label: "Show floating square (off = bar icon only)"; checked: config.showAnchor; onFlipped: config.set("showAnchor", !config.showAnchor) }
        SwitchRow { label: "Pin open (no auto-collapse)"; checked: config.keepOpen; onFlipped: config.set("keepOpen", !config.keepOpen) }

        SectionHeader { text: "Corner & size" }
        Row {
          width: parent.width; spacing: Style.spacing.sm
          Repeater {
            model: ["top-left", "top-right", "bottom-left", "bottom-right"]
            delegate: WidgetButton {
              text: modelData; active: config.corner === modelData
              onPressed: function() { config.set("corner", modelData); }
            }
          }
        }
        Row {
          width: parent.width; spacing: Style.spacing.lg
          Column { width: (parent.width - parent.spacing) / 2; spacing: 2
            RowLabel { text: "Card width (" + config.cardWidth + ")"; width: parent.width }
            PanelSlider {
              width: parent.width
              minimum: 300; maximum: 640; step: 10
              value: config.cardWidth
              onMoved: function(v) { config.set("cardWidth", Math.round(v)); }
            }
          }
          Column { width: (parent.width - parent.spacing) / 2; spacing: 2
            RowLabel { text: "Card height (" + config.cardHeight + ")"; width: parent.width }
            PanelSlider {
              width: parent.width
              minimum: 320; maximum: 900; step: 10
              value: config.cardHeight
              onMoved: function(v) { config.set("cardHeight", Math.round(v)); }
            }
          }
        }
        Row {
          width: parent.width; spacing: Style.spacing.lg
          Column { width: (parent.width - parent.spacing) / 2; spacing: 2
            RowLabel { text: "Margin X (" + config.cornerMarginX + ")"; width: parent.width }
            PanelSlider {
              width: parent.width
              minimum: 0; maximum: 200; step: 1
              value: config.cornerMarginX
              onMoved: function(v) { config.set("cornerMarginX", Math.round(v)); }
            }
          }
          Column { width: (parent.width - parent.spacing) / 2; spacing: 2
            RowLabel { text: "Margin Y (" + config.cornerMarginY + ")"; width: parent.width }
            PanelSlider {
              width: parent.width
              minimum: 0; maximum: 200; step: 1
              value: config.cornerMarginY
              onMoved: function(v) { config.set("cornerMarginY", Math.round(v)); }
            }
          }
        }
        RowLabel { text: "Square size (" + config.buttonSize + ")"; width: parent.width }
        PanelSlider {
          width: parent.width
          minimum: 40; maximum: 96; step: 2
          value: config.buttonSize
          onMoved: function(v) { config.set("buttonSize", Math.round(v)); }
        }

        // ---- Timing & motion ----
        SectionHeader { text: "Hover & motion" }
        Row {
          width: parent.width; spacing: Style.spacing.lg
          Column { width: (parent.width - parent.spacing) / 2; spacing: 2
            RowLabel { text: "Hover to open (" + config.openDelay + "ms)"; width: parent.width }
            PanelSlider { width: parent.width; minimum: 0; maximum: 1500; step: 10; value: config.openDelay; onMoved: function(v) { config.set("openDelay", Math.round(v)); } }
          }
          Column { width: (parent.width - parent.spacing) / 2; spacing: 2
            RowLabel { text: "Leave to close (" + config.closeDelay + "ms)"; width: parent.width }
            PanelSlider { width: parent.width; minimum: 250; maximum: 3000; step: 10; value: config.closeDelay; onMoved: function(v) { config.set("closeDelay", Math.round(v)); } }
          }
        }
        RowLabel { text: "Motion duration (" + config.motionDuration + "ms)"; width: parent.width }
        PanelSlider { width: parent.width; minimum: 0; maximum: 600; step: 5; value: config.motionDuration; onMoved: function(v) { config.set("motionDuration", Math.round(v)); } }
        SwitchRow { label: "Reduced motion"; checked: config.reducedMotion; onFlipped: config.set("reducedMotion", !config.reducedMotion) }

        // ---- Mounter behavior ----
        SectionHeader { text: "Mounter" }
        SwitchRow { label: "Auto-lock LUKS after unmount"; checked: config.lockOnUnmount; onFlipped: config.set("lockOnUnmount", !config.lockOnUnmount) }
        SwitchRow { label: "Show system devices (OS, EFI, recovery)"; checked: config.showSystem; onFlipped: config.set("showSystem", !config.showSystem) }
        RowLabel { text: "Rescan interval (" + config.pollMs + "ms)"; width: parent.width }
        PanelSlider { width: parent.width; minimum: 1000; maximum: 15000; step: 250; value: config.pollMs; onMoved: function(v) { config.set("pollMs", Math.round(v)); } }
        RowLabel {
          width: parent.width; wrapMode: Text.WordWrap
          color: Util.alpha(root.contentForeground, 0.7)
          font.pixelSize: Style.font.caption
          text: "Mounts via udisks2 — no sudo needed. The drive running the OS is never listed. LUKS passphrases go through a 700-dir key file that is shredded after unlock, never via argv."
        }

        Row {
          width: parent.width; spacing: Style.spacing.sm
          WidgetButton { text: "Reset settings"; onPressed: function() { config.resetAll(); } }
          WidgetButton { text: "Close"; onPressed: function() { root.close(); } }
        }
      }
    }
  }
}
