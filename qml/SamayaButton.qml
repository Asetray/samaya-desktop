import QtQuick
import QtQuick.Controls.Basic

AbstractButton {
    id: control
    property string glyph: ""
    property string trailingGlyph: ""
    property real trailingGlyphRotation: 0
    property string kind: "quiet"
    property bool activeWork: false
    property bool selected: false
    property bool alignLeft: false
    property string hint: ""
    property int glyphSize: 16
    property int typeSize: 14
    property int labelPadding: 12
    property int trailingSpace: 0
    readonly property int labelMargins: 2 * labelPadding + trailingSpace + (glyph ? glyphSize + 8 : 0) + (trailingGlyph ? 22 : 0)
    property color foreground: kind === "primary" ? Style.primaryText : Style.ink
    property color fill: kind === "primary" ? Style.primary : selected ? Style.selected : hovered ? Style.hover : kind === "outline" ? Style.surface : "transparent"
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    TextMetrics {
        id: measure
        text: control.text
        font.family: Style.family
        font.pixelSize: control.typeSize
    }
    implicitWidth: text.length ? Math.ceil(measure.advanceWidth) + labelMargins : 32
    implicitHeight: 36
    Accessible.name: text || hint
    ToolTip.visible: hovered && hint.length > 0
    ToolTip.text: hint
    ToolTip.delay: 550
    opacity: enabled ? 1 : 0.45
    background: Rectangle {
        radius: 8
        color: control.fill
        border.color: control.visualFocus ? Style.focus : control.kind === "outline" ? Style.border : "transparent"
        border.width: control.visualFocus ? 2 : 1
    }
    contentItem: Item {
        Row {
            id: body
            x: control.alignLeft ? control.labelPadding : Math.max(0, (parent.width - width) / 2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Image {
                id: symbol
                RotationAnimation on rotation {
                    running: control.visible && control.glyph.indexOf("spinner") >= 0 && !desktop.reducedMotion
                    from: 0
                    to: 360
                    duration: 800
                    loops: Animation.Infinite
                }
                visible: !!control.glyph
                width: visible ? control.glyphSize : 0
                height: width
                sourceSize: Qt.size(control.glyphSize * 2, control.glyphSize * 2)
                anchors.verticalCenter: parent.verticalCenter
                source: visible ? Style.symbol(control.glyph, control.foreground) : ""
            }
            Ink {
                id: label
                visible: !!control.text
                text: control.text
                font.pixelSize: control.typeSize
                color: control.activeWork && !desktop.reducedMotion ? "transparent" : control.foreground
                Canvas {
                    id: shine
                    anchors.fill: parent
                    visible: control.activeWork && !desktop.reducedMotion
                    property real phase: 0
                    NumberAnimation on phase {
                        from: 0
                        to: 1
                        duration: 1800
                        loops: Animation.Infinite
                        running: shine.visible
                    }
                    onPhaseChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        if (width <= 0 || height <= 0)
                            return;
                        const x = (phase * 2.4 - 0.9) * width, g = ctx.createLinearGradient(x - width, 0, x + width, height * 0.26);
                        g.addColorStop(0.35, String(Style.muted));
                        g.addColorStop(0.50, String(Style.ink));
                        g.addColorStop(0.65, String(Style.muted));
                        ctx.fillStyle = g;
                        ctx.font = control.typeSize + "px '" + Style.family + "'";
                        // Match the baseline of the label used in reduced-motion mode.
                        ctx.textBaseline = "alphabetic";
                        ctx.fillText(label.text, 0, label.baselineOffset);
                    }
                }
                width: Math.min(implicitWidth, Math.max(0, control.width - control.labelMargins))
                anchors.verticalCenter: parent.verticalCenter
            }
            Image {
                visible: !!control.trailingGlyph
                width: visible ? 14 : 0
                height: width
                rotation: control.trailingGlyphRotation
                sourceSize: Qt.size(28, 28)
                anchors.verticalCenter: parent.verticalCenter
                source: visible ? Style.symbol(control.trailingGlyph, control.foreground) : ""
            }
        }
    }
}
