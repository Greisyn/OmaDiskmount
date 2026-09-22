import QtQuick
import qs.Commons

// Theme-following line icons for the mounter, same 22x22 1.5px
// round-cap language as oShelf / cliamp-dock glyphs.
Canvas {
  id: root
  property string kind: "drive"
  property color ink: Color.foreground
  width: 22; height: 22
  onKindChanged: requestPaint()
  onInkChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var c = getContext("2d");
    c.reset(); c.strokeStyle = ink; c.fillStyle = ink;
    c.lineWidth = 1.5; c.lineJoin = "round"; c.lineCap = "round";
    c.scale(width / 22, height / 22);
    c.beginPath();
    if (kind === "drive") {
      c.rect(3, 7, 16, 9);
      c.moveTo(6, 19); c.lineTo(16, 19);
      c.moveTo(6.5, 10.5); c.arc(6, 10.5, 0.9, 0, Math.PI * 2); c.fill();
    } else if (kind === "lock") {
      c.rect(6, 10, 10, 8);
      c.moveTo(8, 10); c.lineTo(8, 7.5); c.arc(11, 7.5, 3, Math.PI, 0);
      c.lineTo(14, 10);
      c.moveTo(11.4, 13); c.arc(11, 13.4, 1, 0, Math.PI * 2); c.fill();
    } else if (kind === "unlock") {
      c.rect(6, 10, 10, 8);
      c.moveTo(8, 10); c.lineTo(8, 7.5); c.arc(11, 7.5, 3, Math.PI, 0.3);
      c.moveTo(6.5, 13.4); c.arc(11, 13.4, 0, 0, 0); // noop keep path warm
      c.moveTo(11.4, 13); c.arc(11, 13.4, 1, 0, Math.PI * 2); c.fill();
    } else if (kind === "eject") {
      c.moveTo(11, 4); c.lineTo(17, 12); c.lineTo(5, 12); c.closePath();
      c.moveTo(6, 15); c.lineTo(16, 15);
    } else if (kind === "mount") {
      c.moveTo(11, 3); c.lineTo(11, 13);
      c.moveTo(7, 9); c.lineTo(11, 13); c.lineTo(15, 9);
      c.moveTo(5, 16); c.lineTo(17, 16);
    } else if (kind === "open") {
      c.rect(4, 6, 14, 11);
      c.moveTo(4, 6); c.lineTo(11, 11); c.lineTo(18, 6);
    } else if (kind === "power") {
      c.moveTo(11, 3); c.lineTo(11, 11);
      c.arc(11, 12, 6.5, -0.4 + Math.PI / 2, 0.4 + Math.PI * 1.5);
    } else if (kind === "refresh") {
      c.arc(11, 11, 7, 0.9, 0.9 + Math.PI * 1.5);
      c.moveTo(16.5, 6.6); c.lineTo(16.8, 10.6);
      c.moveTo(16.5, 6.6); c.lineTo(13, 7.4);
    } else if (kind === "pin") {
      c.moveTo(7, 3); c.lineTo(15, 3); c.lineTo(14, 10);
      c.lineTo(17, 14); c.lineTo(5, 14); c.lineTo(8, 10); c.closePath();
      c.moveTo(11, 14); c.lineTo(11, 20);
    } else if (kind === "close") {
      c.moveTo(6, 6); c.lineTo(16, 16); c.moveTo(16, 6); c.lineTo(6, 16);
    } else if (kind === "check") {
      c.moveTo(5, 12); c.lineTo(10, 17); c.lineTo(17, 6);
    }
    c.stroke();
  }
}
