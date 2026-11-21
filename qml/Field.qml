import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: field
    implicitHeight: 40
    font.family: Style.family
    font.pixelSize: 14
    property bool searchIcon: false
    Image {
        visible: field.searchIcon
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        source: visible ? Style.symbol("search", Style.muted) : ""
    }
    leftPadding: searchIcon ? 38 : 12
    rightPadding: 12
    color: Style.ink
    placeholderTextColor: Style.quiet
    selectionColor: Style.textSelection
    selectedTextColor: Style.ink
    background: Rectangle {
        color: Style.surface
        radius: 6
        border.color: field.activeFocus ? Style.focus : Style.border
    }
}
