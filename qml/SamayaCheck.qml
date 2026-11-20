import QtQuick
import QtQuick.Controls.Basic

CheckBox {
    id: control
    padding: 4
    spacing: 10
    leftPadding: 4
    implicitHeight: 32
    indicator: Rectangle {
        width: 16
        height: 16
        x: control.leftPadding
        y: (control.height - height) / 2
        radius: 4
        color: control.checked ? Style.accent : Style.bg
        border.color: control.visualFocus ? Style.focus : Style.border
        Image {
            anchors.centerIn: parent
            width: 12
            height: 12
            visible: control.checked
            source: Style.symbol("wm-check", Style.primaryText)
        }
    }
    contentItem: Ink {
        leftPadding: 22
        text: control.text
        font.pixelSize: 13
    }
}
