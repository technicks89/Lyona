import QtQuick
import QtQuick.Layouts
import qs.core

Text {
    textFormat: Text.PlainText
    required property string label

    Layout.fillWidth: true
    text: label.toUpperCase()
    color: Theme.menuMutedText
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontBodySmallSize
    font.bold: true
    font.letterSpacing: Theme.panelMetaLetterSpacing
    elide: Text.ElideRight
}
