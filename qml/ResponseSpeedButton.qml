import QtQuick
import "Util.js" as U

SamayaButton {
    id: button
    property string serviceTier: "default"
    property color iconColor: Style.ink

    implicitWidth: 28
    implicitHeight: 28
    Accessible.name: "响应速度 · " + U.speedLabel(serviceTier)

    contentItem: Item {
        Image {
            objectName: "speedLightning"
            anchors.centerIn: parent
            width: 12
            height: 16
            sourceSize: Qt.size(24, 32)
            source: Style.symbol(button.serviceTier === "default" ? "speed-lightning-outline" : "speed-lightning", button.iconColor)
        }
    }
}
