pragma Singleton
import QtQuick

QtObject {
    property bool dark: false
    readonly property string family: "Noto Sans SC"
    readonly property color bg: dark ? "#080a0d" : "#f8f7f2"
    readonly property color rail: dark ? "#0b0f13" : "#f3f1ea"
    readonly property color surface: dark ? "#111820" : "#fcfbf8"
    readonly property color subtle: dark ? "#151e27" : "#eeece5"
    readonly property color selected: dark ? "#1d2b37" : "#e3e9e5"
    readonly property color textSelection: dark ? selected : "#dce4e0"
    readonly property color hover: dark ? "#16212a" : "#edf1ee"
    readonly property color railHover: dark ? hover : "#dce4e0"
    readonly property color border: dark ? "#273746" : "#d8dcd7"
    readonly property color ink: dark ? "#e7eef4" : "#252a2a"
    readonly property color muted: dark ? "#aab7c3" : "#656c69"
    readonly property color quiet: dark ? "#7c8b98" : "#858d89"
    readonly property color accent: dark ? "#9fc4e2" : "#5d706c"
    readonly property color link: dark ? "#b4d2e9" : "#5d706c"
    readonly property color linkHover: dark ? Qt.lighter(link, 1.22) : Qt.darker(link, 1.28)
    readonly property color primary: dark ? "#9fc4e2" : "#252a2a"
    readonly property color primaryText: dark ? "#080a0d" : "#fcfbf8"
    readonly property color focus: dark ? "#789fbe" : "#78968f"
    function symbol(name, color) {
        return "image://symbols/" + name + "/" + String(color).slice(1);
    }
}
