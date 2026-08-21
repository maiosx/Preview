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
  property bool selectable: true
  readonly property string kind: String(preview && preview.kind ? preview.kind : "")
  readonly property string bodyText: {
    if (preview && preview.text) return String(preview.text)
    if (preview && preview.hex) return String(preview.hex)
    if (preview && preview.html)
      return String(preview.html).replace(/<[^>]+>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
    return String((preview && preview.label) || "")
  }

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
      visible: root.kind === "code" || root.kind === "csv" || root.kind === "hex" || root.kind === "video"
      clip: true
      contentWidth: width
      contentHeight: Math.max(height, body.implicitHeight)
      boundsBehavior: Flickable.StopAtBounds
      TextEdit {
        id: body
        width: parent.width
        readOnly: true
        selectByMouse: root.selectable
        persistentSelection: true
        text: root.bodyText
        textFormat: TextEdit.PlainText
        color: root.foreground
        font.family: root.monoFamily
        font.pixelSize: Style.font.body
        wrapMode: TextEdit.Wrap
        activeFocusOnPress: root.selectable
        cursorVisible: false
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

    Text {
      anchors.centerIn: parent
      visible: !root.loading && root.kind === ""
      text: "select a file"
      color: root.foreground
      opacity: 0.45
    }
  }
}
