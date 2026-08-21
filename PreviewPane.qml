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
      opacity: 0.7
    }

    Image {
      anchors.fill: parent
      anchors.margins: 12
      visible: root.kind === "image" && !root.loading
      source: preview.path ? Format.fileUrl(preview.path) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: false
    }

    Flickable {
      anchors.fill: parent
      anchors.margins: 14
      visible: root.kind === "code" || root.kind === "csv"
      clip: true
      contentWidth: width
      contentHeight: body.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      Text {
        id: body
        width: parent.width
        text: preview.html ? preview.html : (preview.label || "")
        textFormat: preview.html ? Text.RichText : Text.PlainText
        color: root.foreground
        font.family: root.monoFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }
    }

    Text {
      anchors.centerIn: parent
      width: parent.width - 40
      visible: root.kind === "pdf" && preview.need_poppler
      text: "install poppler for PDF text\npacman -S poppler"
      color: root.foreground
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
    }

    Flickable {
      anchors.fill: parent
      anchors.margins: 14
      visible: root.kind === "hex" || root.kind === "video"
      clip: true
      contentHeight: hexCol.implicitHeight
      contentWidth: width
      Column {
        id: hexCol
        width: parent.width
        spacing: 8
        Text { text: preview.label || "can't render this"; color: root.accent }
        Text {
          width: parent.width
          text: preview.hex || ""
          color: root.foreground
          wrapMode: Text.Wrap
          font.family: root.monoFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Text {
      anchors.centerIn: parent
      visible: !root.loading && root.kind === ""
      text: "select a file"
      color: root.foreground
      opacity: 0.45
    }
  }
}
