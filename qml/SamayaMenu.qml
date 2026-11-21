import QtQuick
import QtQuick.Controls.Basic

Menu {
    popupType: Popup.Item
    implicitWidth: 200
    padding: 6
    margins: 8
    delegate: SamayaMenuItem {}

    background: Rectangle {
        color: Style.surface
        border.color: Style.border
        border.width: 1
        radius: 8
    }
}
