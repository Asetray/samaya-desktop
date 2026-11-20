import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Item {
    id: view
    required property var appRoot
    property var threads: []
    property var selected: []
    property string cursor: ""
    property int serial: 0
    property bool loading: false
    property bool archived: false
    property string state: "全部状态"
    property bool ascending: false
    property bool reviewing: false
    property string operation: ""
    property var plans: []
    property var failures: []
    property bool confirming: false
    property var reselect: []
    readonly property var shown: {
        const list = threads.filter(t => state === "全部状态" || (state === "运行中") === U.active(t));
        return ascending ? list.slice().reverse() : list;
    }
    function load(append) {
        if (reviewing || confirming)
            return;
        const n = ++serial;
        if (!append) {
            cursor = "";
            threads = [];
            selected = [];
        }
        if (!appRoot.online) {
            loading = false;
            return;
        }
        loading = true;
        desktop.read("/threads", {
            cwd: appRoot.workspaceFilter,
            search: query.text,
            archived: archived,
            cursor: append ? cursor : ""
        }, (d, e) => {
            if (n !== serial)
                return;
            loading = false;
            if (e) {
                appRoot.tell(e);
                return;
            }
            threads = append ? threads.concat(d.data || []) : d.data || [];
            cursor = d.nextCursor || "";
            if (reselect.length) {
                selected = reselect.filter(id => threads.some(t => t.id === id));
                reselect = [];
            }
        });
    }
    function select(id) {
        selected = selected.includes(id) ? selected.filter(i => i !== id) : selected.concat([id]);
    }
    function prepare(op) {
        if (!selected.length || reviewing || confirming || !appRoot.online)
            return;
        operation = op;
        plans = [];
        failures = [];
        reviewing = true;
        const ids = selected.slice();
        function next(index) {
            if (index >= ids.length) {
                reviewing = false;
                if (plans.length) {
                    confirming = true;
                    review.open();
                } else
                    appRoot.tell(failures.join("\n"));
                return;
            }
            desktop.read("/threads/" + encodeURIComponent(ids[index]) + "/cleanup-preview", {}, (d, e) => {
                if (e)
                    failures = failures.concat([ids[index] + " · " + e]);
                else
                    plans = plans.concat([
                        {
                            id: ids[index],
                            scope: d.scope,
                            digest: d.digest
                        }
                    ]);
                next(index + 1);
            });
        }
        next(0);
    }
    function commit() {
        if (!confirming || !appRoot.online || appRoot.busy)
            return;
        const entries = plans.slice(), retry = failures.slice(), left = selected.slice();
        confirming = false;
        review.close();
        reviewing = true;
        function step(index) {
            if (index >= entries.length || !appRoot.online) {
                reviewing = false;
                reselect = left;
                load(false);
                if (retry.length)
                    appRoot.tell(retry.join("\n"));
                return;
            }
            const p = entries[index];
            appRoot.act(operation, {
                threadId: p.id,
                digest: p.digest
            }, (d, e) => {
                if (e)
                    retry.push(p.id + " · " + e);
                else
                    left.splice(left.indexOf(p.id), 1);
                step(index + 1);
            });
        }
        step(0);
    }
    Connections {
        target: appRoot
        function onOnlineChanged() {
            if (appRoot.online && view.visible)
                view.load(false);
        }
    }
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        y: appRoot.compact ? 48 : 24
        width: Math.min(912, view.width - (appRoot.compact ? 32 : 72))
        height: parent.height - y - 20
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Ink {
                Layout.fillWidth: true
                text: appRoot.workspaceFilter ? "工作区管理" : "记录管理"
                font.pixelSize: 30
                font.weight: Font.Medium
            }
            SamayaButton {
                text: "←  返回任务总览"
                onClicked: appRoot.overview("任务总览")
            }
        }
        Column {
            visible: !!appRoot.workspaceFilter
            Layout.fillWidth: true
            Ink {
                text: U.base(appRoot.workspaceFilter)
                font.pixelSize: 20
                font.weight: Font.Medium
            }
            Ink {
                text: appRoot.workspaceFilter
                color: Style.muted
                font.pixelSize: 12
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 16
            enabled: !view.reviewing
            spacing: 8
            Field {
                id: query
                Layout.fillWidth: true
                Layout.maximumWidth: 320
                Layout.minimumWidth: 64
                searchIcon: true
                placeholderText: "搜索对话"
                onTextEdited: searchDelay.restart()
            }
            SamayaButton {
                kind: "outline"
                text: view.archived ? "已归档 ﹀" : "全部对话 ﹀"
                onClicked: types.open()
                Menu {
                    id: types
                    MenuItem {
                        text: "全部对话"
                        onTriggered: {
                            view.archived = false;
                            view.load(false);
                        }
                    }
                    MenuItem {
                        text: "已归档"
                        onTriggered: {
                            view.archived = true;
                            view.load(false);
                        }
                    }
                }
            }
            SamayaButton {
                visible: !appRoot.compact
                kind: "outline"
                text: view.state + " ﹀"
                onClicked: conditions.open()
                Menu {
                    id: conditions
                    Repeater {
                        model: ["全部状态", "运行中", "已结束"]
                        MenuItem {
                            required property string modelData
                            text: modelData
                            onTriggered: view.state = text
                        }
                    }
                }
            }
            Item {
                Layout.fillWidth: true
                visible: !appRoot.compact
            }
            SamayaButton {
                kind: "primary"
                glyph: "plus"
                text: appRoot.compact ? "" : "新建对话"
                onClicked: appRoot.newThread(appRoot.workspaceFilter)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            enabled: !view.reviewing
            SamayaCheck {
                text: view.selected.length ? "已选 " + view.selected.length : "全选当前列表"
                palette.text: Style.ink
                font.family: Style.family
                checked: view.shown.length > 0 && view.shown.every(t => view.selected.includes(t.id))
                onClicked: view.selected = checked ? view.shown.map(t => t.id) : []
            }
            SamayaButton {
                visible: view.selected.length > 0 && !view.archived
                text: "归档"
                glyph: "wm-archive"
                onClicked: view.prepare("archive")
            }
            SamayaButton {
                visible: view.selected.length > 0
                text: "删除"
                glyph: "wm-trash"
                onClicked: view.prepare("delete")
            }
            Item {
                Layout.fillWidth: true
            }
            Ink {
                visible: !appRoot.compact
                text: view.shown.length + " 个对话"
                color: Style.muted
                font.pixelSize: 12
            }
            SamayaButton {
                visible: !appRoot.compact
                text: view.ascending ? "最早活动" : "最近活动"
                kind: "outline"
                onClicked: view.ascending = !view.ascending
            }
        }
        Ink {
            text: view.reviewing ? "正在核对记录…" : view.ascending ? "已按最早活动排序" : "已按最近活动排序"
            font.pixelSize: 12
            color: Style.muted
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: view.shown
            ScrollBar.vertical: ScrollBar {}
            delegate: RowLayout {
                required property var modelData
                width: list.width - 8
                height: 72
                spacing: 8
                SamayaCheck {
                    checked: view.selected.includes(modelData.id)
                    enabled: !view.reviewing
                    Accessible.name: U.title(modelData)
                    onClicked: view.select(modelData.id)
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Ink {
                        text: U.title(modelData)
                        Layout.fillWidth: true
                    }
                    Ink {
                        Layout.fillWidth: true
                        text: U.status(modelData) + " · " + U.date(modelData.updatedAt)
                        font.pixelSize: 12
                        color: Style.muted
                    }
                }
                SamayaButton {
                    visible: view.archived
                    kind: "outline"
                    text: "恢复"
                    enabled: !appRoot.busy
                    onClicked: appRoot.act("unarchive", {
                        threadId: modelData.id
                    }, () => view.load(false))
                }
                SamayaButton {
                    kind: "outline"
                    text: "进入对话"
                    onClicked: appRoot.openThread(modelData.id)
                }
            }
            Ink {
                visible: list.count === 0
                anchors.centerIn: parent
                text: view.loading ? "正在读取…" : "没有符合条件的对话"
                color: Style.muted
            }
        }
        SamayaButton {
            visible: !!view.cursor
            Layout.alignment: Qt.AlignRight
            text: "加载更多"
            enabled: !view.loading
            onClicked: view.load(true)
        }
    }
    Timer {
        id: searchDelay
        interval: 200
        onTriggered: view.load(false)
    }
    Sheet {
        id: review
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(560, appRoot.width - 32)
        height: Math.min(440, appRoot.height - 72)
        onClosed: view.confirming = false
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Ink {
                text: view.operation === "archive" ? "确认归档对话" : "确认永久删除对话"
                font.pixelSize: 20
                font.weight: Font.Medium
            }
            Ink {
                Layout.fillWidth: true
                text: "此次操作涉及以下对话及子会话。"
                wrapMode: Text.Wrap
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                Column {
                    width: review.availableWidth
                    spacing: 8
                    Repeater {
                        model: view.plans.reduce((a, p) => a.concat(p.scope), [])
                        Ink {
                            required property var modelData
                            width: parent.width
                            text: (modelData.name || modelData.id) + "　" + modelData.cwd
                            wrapMode: Text.Wrap
                        }
                    }
                    Ink {
                        width: parent.width
                        text: view.failures.join("\n")
                        wrapMode: Text.Wrap
                        color: Style.muted
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                SamayaButton {
                    text: "取消"
                    onClicked: review.close()
                }
                SamayaButton {
                    kind: "primary"
                    text: view.operation === "archive" ? "确认归档" : "永久删除"
                    onClicked: view.commit()
                }
            }
        }
    }
}
