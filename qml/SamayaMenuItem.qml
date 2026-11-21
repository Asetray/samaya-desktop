import QtQuick
import QtQuick.Controls.Basic

MenuItem {
    id: action
    readonly property bool keyboardHighlight: highlighted && (visualFocus || !hovered)
    hoverEnabled: true
    implicitHeight: 32
    leftPadding: 12
    rightPadding: 12
    topPadding: 0
    bottomPadding: 0
    font.family: Style.family
    font.pixelSize: 14
    contentItem: Ink {
        text: action.text
        font: action.font
        color: action.enabled ? Style.ink : Style.muted
    }
    background: Rectangle {
        radius: 6
        color: {
            if (!action.enabled)
                return "transparent";
            if (action.down || action.keyboardHighlight)
                return Style.selected;
            return action.hovered || action.highlighted ? Style.hover : "transparent";
        }
        border.width: action.enabled && action.keyboardHighlight ? 1 : 0
        border.color: Style.focus
    }
}
