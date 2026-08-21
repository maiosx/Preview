import QtQuick
import qs.Commons
import "js/Format.js" as Format

Item {
  id: root
  property var preview: ({})
  property string emptyReason: ""
  property string emptyDetail: ""
  property bool loading: false
  property var palette: ({})
  property color foreground: "#c0caf5"
  property color accent: "#7aa2f7"
  property string fontFamily: "sans-serif"
  property string monoFamily: "monospace"
  property int pinPage: 1
  readonly property string kind: String(preview && preview.kind ? preview.kind : "")

  Rectangle {
    anchors.fill: parent
    color: "transparent"

    Text {
      anchors.centerIn: parent
      visible: root.loading && root.kind === ""
      text: "rendering…"
      color: root.foreground
    }

    Image {
      anchors.fill: parent
      anchors.margins: 12
      visible: root.kind === "image"
      source: preview.path ? Format.fileUrl(preview.path) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }

    Text {
      anchors.centerIn: parent
      width: parent.width - 40
      visible: root.kind !== "image" && !root.loading
      text: root.emptyReason.length ? root.emptyReason : (preview.label || preview.kind || "select a file")
      color: root.foreground
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
