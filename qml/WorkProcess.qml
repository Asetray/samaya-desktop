import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

ColumnLayout {
    id: process
    required property var entry
    required property var appRoot
    required property var disclosureState
    signal resizing(Item item)

    property bool expanded: !!disclosureState[entry.key]
    property double now: Date.now()
    readonly property bool waiting: entry.active && (appRoot.currentRequests || []).length > 0
    readonly property bool stale: entry.active && ((appRoot.thread || {}).status || {}).type === "systemError"
    readonly property bool running: entry.active && appRoot.online && !waiting && !stale
    readonly property var latestActivity: {
        const groups = entry.rows.filter(row => row.items);
        return groups.slice().reverse().find(row => row.items.some(record => record.item.status === "inProgress"))
            || groups[groups.length - 1];
    }
    readonly property var latestComment: entry.rows.slice().reverse().find(row => row.kind === "agentMessage")
    readonly property bool hasDuration: entry.startedAt !== undefined && entry.completedAt >= entry.startedAt
    readonly property string stateLabel: {
        if (entry.status === "failed")
            return "本轮失败";
        if (entry.status === "interrupted")
            return "本轮已中断";
        if (!entry.active)
            return entry.status === "inProgress" ? "此前过程" : "本轮已结束";
        if (!appRoot.online)
            return "连接已断开";
        if (waiting)
            return "等待你的答复";
        if (stale)
            return "状态待确认";
        if (entry.hasFinal)
            return "正在生成答复";
        if (latestActivity && latestActivity.items.some(record => record.item.status === "inProgress"))
            return "正在" + latestActivity.label;
        return "正在处理";
    }
    readonly property string summary: {
        const parts = [];
        if (entry.status !== "completed" || !hasDuration)
            parts.push(stateLabel);
        if (hasDuration)
            parts.push("已用时 " + U.durationLabel(entry.completedAt - entry.startedAt));
        else if (entry.active && entry.startedAt !== undefined)
            parts.push("已用时 " + U.durationLabel(now - entry.startedAt));
        else
            parts.push(entry.active ? "计时待确认" : "耗时未提供");
        return parts.join(" · ");
    }

    spacing: 8
    Timer {
        interval: 1000
        running: process.running && process.entry.startedAt !== undefined
        repeat: true
        onRunningChanged: if (running) process.now = Date.now()
        onTriggered: process.now = Date.now()
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            SamayaButton {
                id: disclosure
                objectName: "workProcessToggle"
                visible: process.entry.rows.length > 0
                Layout.maximumWidth: process.width
                text: process.summary
                hint: implicitWidth > width ? process.summary : ""
                alignLeft: true
                activeWork: process.running
                foreground: Style.muted
                trailingGlyph: "chevron"
                trailingGlyphRotation: process.expanded ? 90 : 0
                Accessible.description: process.expanded ? "收起本轮过程" : "展开本轮过程"
                onClicked: {
                    process.resizing(disclosure);
                    process.expanded = !process.expanded;
                    process.disclosureState[process.entry.key] = process.expanded;
                }
            }
            Ink {
                visible: !disclosure.visible
                Layout.preferredHeight: disclosure.implicitHeight
                leftPadding: disclosure.labelPadding
                color: Style.muted
                text: process.summary
            }
            Item { Layout.fillWidth: true }
        }
        Ink {
            objectName: "workProcessCount"
            visible: !!text
            Layout.fillWidth: true
            font.pixelSize: 12
            color: Style.muted
            text: [
                process.expanded && process.entry.toolCount ? process.entry.toolCount + " 次活动" : "",
                process.entry.failures ? process.entry.failures + " 项工具异常" : ""
            ].filter(Boolean).join(" · ")
        }
    }
    Repeater {
        model: StableRows {
            source: process.expanded ? process.entry.rows
                : process.entry.active && !process.entry.hasFinal
                  ? process.entry.rows.filter(row => row === process.latestActivity || row === process.latestComment) : []
            keyFor: entry => entry.key
        }
        delegate: Loader {
            id: processRow
            required property QtObject row
            readonly property var record: row.value
            Layout.fillWidth: true
            sourceComponent: record.items ? activity : comment

            Component {
                id: comment
                TextEdit {
                    objectName: "workComment"
                    text: processRow.record.item.text || ""
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    readOnly: true
                    selectByMouse: true
                    font.family: Style.family
                    font.pixelSize: 14
                    color: Style.muted
                }
            }
            Component {
                id: activity
                ColumnLayout {
                    id: group
                    readonly property var record: processRow.record
                    property bool expanded: !!process.disclosureState[record.key]
                    spacing: 4
                    SamayaButton {
                        id: activityButton
                        objectName: "workActivityToggle"
                        Layout.maximumWidth: group.width
                        text: group.record.label + " · " + group.record.items.length + " 次"
                            + (group.record.failures ? " · " + group.record.failures + " 项异常" : "")
                        hint: implicitWidth > width ? text : ""
                        alignLeft: true
                        implicitHeight: 32
                        typeSize: 13
                        foreground: Style.muted
                        trailingGlyph: "chevron"
                        trailingGlyphRotation: group.expanded ? 90 : 0
                        Accessible.description: group.expanded ? "收起工具记录" : "展开工具记录"
                        onClicked: {
                            process.resizing(activityButton);
                            group.expanded = !group.expanded;
                            process.disclosureState[group.record.key] = group.expanded;
                        }
                    }
                    Repeater {
                        model: StableRows {
                            source: group.expanded ? group.record.items : []
                            keyFor: entry => entry.key
                        }
                        delegate: ColumnLayout {
                            required property QtObject row
                            readonly property var item: row.value.item
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            spacing: 4
                            Ink {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.weight: Font.Medium
                                text: item.command || item.tool || item.name || item.type
                            }
                            Ink {
                                visible: process.entry.status !== "inProgress" && item.status === "inProgress"
                                Layout.fillWidth: true
                                color: Style.muted
                                wrapMode: Text.Wrap
                                text: "本轮已结束，此调用的最终状态未提供。"
                            }
                            TextEdit {
                                Layout.fillWidth: true
                                text: U.messageText(item)
                                textFormat: TextEdit.PlainText
                                wrapMode: TextEdit.Wrap
                                readOnly: true
                                selectByMouse: true
                                font.family: "Cascadia Mono"
                                font.pixelSize: 13
                                color: Style.muted
                            }
                        }
                    }
                }
            }
        }
    }
}
