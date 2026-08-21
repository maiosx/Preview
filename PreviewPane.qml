import QtQuick
import QtQuick.Controls
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
  readonly property bool showText: root.kind === "code" || root.kind === "csv" || root.kind === "hex" || root.kind === "video"

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
      id: flick
      anchors.fill: parent
      anchors.margins: 14
      anchors.rightMargin: 22
      visible: root.showText
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: false
      contentWidth: width
      contentHeight: Math.max(height, body.contentHeight)
      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          var maxY = Math.max(0, flick.contentHeight - flick.height)
          var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8
          flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy))
          event.accepted = true
        }
      }
      ScrollBar.vertical: ScrollBar {
        id: vbar
        parent: flick.parent
        anchors.top: flick.top
        anchors.bottom: flick.bottom
        anchors.left: flick.right
        anchors.leftMargin: 4
        policy: flick.contentHeight > flick.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        implicitWidth: 8
        contentItem: Rectangle {
          implicitWidth: 8
          radius: 4
          color: root.accent
          opacity: vbar.hovered || vbar.pressed ? 0.95 : 0.5
        }
        background: Rectangle {
          implicitWidth: 8
          radius: 4
          color: root.foreground
          opacity: 0.12
        }
      }
      TextEdit {
        id: body
        width: flick.width
        height: contentHeight
        readOnly: true
        selectByMouse: root.selectable
        persistentSelection: true
        mouseSelectionMode: TextEdit.SelectCharacters
        text: root.bodyText
        textFormat: TextEdit.PlainText
        color: root.foreground
        font.family: root.monoFamily
        font.pixelSize: Style.font.body
        wrapMode: TextEdit.Wrap
        activeFocusOnPress: root.selectable
        cursorVisible: false
        HoverHandler {
          cursorShape: Qt.IBeamCursor
          enabled: root.selectable
        }
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
