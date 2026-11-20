import QtQuick
import QtQuick.Controls.Basic

Popup {
    id: sheet
    padding: 12
    focus: true
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle {
        color: Style.surface
        border.color: Style.border
        radius: 12
    }
    Overlay.modal: Rectangle {
        color: Qt.rgba(0.1, 0.15, 0.15, 0.07)
    }
}
