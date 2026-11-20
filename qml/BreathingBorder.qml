import QtQuick

Rectangle {
    id: borderLayer
    color: "transparent"
    radius: 8
    border.width: 4
    border.color: Style.accent
    property bool animate: true
    SequentialAnimation on opacity {
        running: borderLayer.visible && borderLayer.animate && !desktop.reducedMotion
        loops: Animation.Infinite
        NumberAnimation {
            from: 1.00000
            to: 0.97907
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0, 0.667, 0.342, 1, 1]
        }
        NumberAnimation {
            from: 0.97907
            to: 0.91945
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.231, 0.667, 0.573, 1, 1]
        }
        NumberAnimation {
            from: 0.91945
            to: 0.83024
            duration: 93
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.285, 0.667, 0.627, 1, 1]
        }
        NumberAnimation {
            from: 0.83024
            to: 0.72500
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.316, 0.667, 0.658, 1, 1]
        }
        NumberAnimation {
            from: 0.72500
            to: 0.61976
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.342, 0.667, 0.684, 1, 1]
        }
        NumberAnimation {
            from: 0.61976
            to: 0.53055
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.373, 0.667, 0.715, 1, 1]
        }
        NumberAnimation {
            from: 0.53055
            to: 0.47093
            duration: 93
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.427, 0.667, 0.769, 1, 1]
        }
        NumberAnimation {
            from: 0.47093
            to: 0.45000
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.658, 0.667, 1, 1, 1]
        }
        NumberAnimation {
            from: 0.45000
            to: 0.47093
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0, 0.667, 0.342, 1, 1]
        }
        NumberAnimation {
            from: 0.47093
            to: 0.53055
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.231, 0.667, 0.573, 1, 1]
        }
        NumberAnimation {
            from: 0.53055
            to: 0.61976
            duration: 93
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.285, 0.667, 0.627, 1, 1]
        }
        NumberAnimation {
            from: 0.61976
            to: 0.72500
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.316, 0.667, 0.658, 1, 1]
        }
        NumberAnimation {
            from: 0.72500
            to: 0.83024
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.342, 0.667, 0.684, 1, 1]
        }
        NumberAnimation {
            from: 0.83024
            to: 0.91945
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.373, 0.667, 0.715, 1, 1]
        }
        NumberAnimation {
            from: 0.91945
            to: 0.97907
            duration: 93
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.427, 0.667, 0.769, 1, 1]
        }
        NumberAnimation {
            from: 0.97907
            to: 1.00000
            duration: 94
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.333, 0.658, 0.667, 1, 1, 1]
        }
        onStopped: borderLayer.opacity = 1
    }
}
