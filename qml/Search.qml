import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Sheet {
    id: box
    required property var appRoot
    property int sequence: 0
    property var hits: []
    property int highlight: 0
    property string issue: ""
    property var fileHits: []
    property var taskHits: []
    function updateHits() {
        const q = query.text.trim().toLowerCase();
        const projects = appRoot.groups.filter(g => !q || g.path.toLowerCase().includes(q)).slice(0, 10).map(g => ({
                    kind: "项目",
                    title: U.base(g.path),
                    desc: g.path,
                    path: g.path,
                    glyph: "search-folder"
                }));
        hits = taskHits.concat(projects, fileHits).slice(0, 60);
        highlight = 0;
    }
    function run() {
        const n = ++sequence, q = query.text.trim();
        issue = "";
        fileHits = [];
        taskHits = appRoot.rows.filter(r => !q || (U.title(r.thread) + " " + r.thread.cwd).toLowerCase().includes(q.toLowerCase())).slice(0, 12).map(r => task(r.thread));
        updateHits();
        if (!appRoot.online || !q)
            return;
        desktop.read("/threads", {
            search: q
        }, (d, e) => {
            if (n !== sequence)
                return;
            if (e) {
                issue = e;
                return;
            }
            taskHits = (d.data || []).map(task);
            updateHits();
        });
        if (appRoot.cwd)
            desktop.read("/files", {
                cwd: appRoot.cwd,
                search: q
            }, (d, e) => {
                if (n !== sequence || e)
                    return;
                fileHits = (d.files || []).slice(0, 8).map(f => ({
                            kind: "文件",
                            title: f.file_name || U.base(f.path),
                            desc: f.path,
                            path: f.path,
                            root: f.root || appRoot.cwd,
                            glyph: "search-file"
                        }));
                updateHits();
            });
    }
    function task(t) {
        return {
            kind: "任务",
            title: U.title(t),
            desc: U.base(t.cwd) + " · " + U.status(t),
            id: t.id,
            glyph: "search-clock"
        };
    }
    function activate(i) {
        const hit = hits[i];
        if (!hit)
            return;
        close();
        if (hit.id)
            appRoot.openThread(hit.id);
        else if (hit.kind === "文件") {
            if (!desktop.openWorkspaceFile(hit.root, hit.path))
                appRoot.tell("无法打开所选文件。");
        } else
            appRoot.recordsFor(hit.path);
    }
    width: Math.min(600, appRoot.width - 32)
    height: Math.min(appRoot.height - 80, 112 + Math.max(52, Math.min(6, hits.length) * 56))
    padding: 8
    onOpened: {
        query.text = "";
        run();
        query.forceActiveFocus();
    }
    onClosed: ++sequence
    ColumnLayout {
        anchors.fill: parent
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Image {
                source: Style.symbol("search", Style.muted)
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                Layout.leftMargin: 12
            }
            Field {
                id: query
                Layout.fillWidth: true
                placeholderText: "搜索任务与项目"
                background: null
                onTextEdited: {
                    ++box.sequence;
                    delay.restart();
                }
                Keys.onDownPressed: {
                    box.highlight = Math.min(box.hits.length - 1, box.highlight + 1);
                    list.positionViewAtIndex(box.highlight, ListView.Contain);
                }
                Keys.onUpPressed: {
                    box.highlight = Math.max(0, box.highlight - 1);
                    list.positionViewAtIndex(box.highlight, ListView.Contain);
                }
                onAccepted: box.activate(box.highlight)
            }
            SamayaButton {
                glyph: "search-close"
                hint: "关闭"
                onClicked: box.close()
            }
        }
        Rectangle {
            height: 1
            Layout.fillWidth: true
            color: Style.border
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: box.hits
            clip: true
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: 56
                radius: 6
                color: index === box.highlight ? Style.hover : "transparent"
                TapHandler {
                    onTapped: box.activate(index)
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    Image {
                        source: Style.symbol(modelData.glyph, Style.muted)
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Ink {
                            Layout.fillWidth: true
                            text: modelData.title
                        }
                        Ink {
                            Layout.fillWidth: true
                            text: modelData.desc
                            color: Style.muted
                            font.pixelSize: 12
                        }
                    }
                    Ink {
                        text: modelData.kind
                        color: Style.muted
                        font.pixelSize: 12
                    }
                }
            }
            Ink {
                anchors.centerIn: parent
                visible: !list.count
                text: box.issue || "没有找到匹配项"
                color: Style.muted
            }
        }
        Ink {
            text: "↑ ↓ 选择    Enter 打开    Esc 关闭"
            color: Style.muted
            font.pixelSize: 12
            Layout.leftMargin: 12
        }
    }
    Timer {
        id: delay
        interval: 160
        onTriggered: box.run()
    }
}
