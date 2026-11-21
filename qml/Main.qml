import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

ApplicationWindow {
    id: app
    visible: true
    width: Math.min(1440, Screen.desktopAvailableWidth)
    height: Math.min(960, Math.max(480, Screen.desktopAvailableHeight - 48))
    minimumWidth: 320
    minimumHeight: 480
    title: "Samaya"
    color: Style.bg
    font.family: Style.family
    property int appearance: Number(desktop.setting("appearance/theme", 0))
    property bool online: false
    property bool connecting: false
    property bool loginNeeded: false
    property string problem: ""
    property string page: "overview"
    property string scope: "任务总览"
    property bool collapsed: false
    property bool drawer: false
    readonly property bool compact: width < 800
    property var rows: []
    property var pending: []
    property var groups: U.grouped(rows)
    property var pins: {
        const stored = desktop.setting("workspace/pins", []);
        if (typeof stored === "string") {
            try {
                const parsed = JSON.parse(stored);
                return Array.isArray(parsed) ? parsed : [];
            } catch (_) {
                return [];
            }
        }
        return Array.from(stored || []);
    }
    property string currentId: ""
    property string openingThreadId: ""
    property int openThreadSeq: 0
    readonly property bool showOpeningThread: !!openingThreadId && !openingIndicator.running
    onOpeningThreadIdChanged: {
        if (openingThreadId)
            openingIndicator.restart();
        else
            openingIndicator.stop();
    }
    Timer {
        id: openingIndicator
        interval: 180
    }
    property string cwd: ""
    property var thread: ({})
    property var currentRequests: pending.filter(r => r.params.threadId === currentId)
    property string tab: "对话"
    property bool busy: false
    property string historyCursor: ""
    property bool historyExtended: false
    property bool loadingOlder: false
    onSelectionChanged: {
        historyCursor = "";
        historyExtended = false;
        loadingOlder = false;
    }
    property bool reading: false
    property int selection: 0
    property int monitorSeq: 0
    property int detailSeq: 0
    property var drafts: ({})
    property var usage: ({})
    property var account: ({})
    property var activeModel: ({})
    property int modelSettingsRevision: 0
    property var catalog: []
    property var selectionSettings: ({})
    property var blockedModelChoice: null
    property string notice: ""
    property string workspaceFilter: ""
    property bool initialized: false
    property var previewImage: ""
    Binding {
        target: Style
        property: "dark"
        value: app.appearance === 2 || (app.appearance === 0 && desktop.systemDark)
    }
    function syncWindowFrame() {
        if (visible)
            desktop.styleWindowFrame(app, Style.dark, Style.bg, Style.ink, Style.border);
    }
    onVisibleChanged: if (visible) Qt.callLater(syncWindowFrame)
    Connections {
        target: Style
        function onDarkChanged() { Qt.callLater(app.syncWindowFrame); }
    }
    function tell(msg) {
        if (msg) {
            notice = msg;
            noticeTimer.restart();
        }
    }
    Timer {
        id: noticeTimer
        interval: 5000
        onTriggered: app.notice = ""
    }
    function connectExisting() {
        if (connecting)
            return;
        connecting = true;
        problem = "";
        desktop.connectServer((d, e) => {
            connecting = false;
            online = !e;
            problem = e;
            if (!e) {
                refreshAccount();
                refreshMonitor();
                if (currentId)
                    refreshThread(true);
            }
        });
    }
    function refreshAccount() {
        desktop.read("/account", {}, (d, e) => {
            if (!e) {
                account = d.account || {};
                loginNeeded = d.requiresOpenaiAuth && !d.account;
            }
        });
    }
    function refreshMonitor() {
        if (!online)
            return;
        const seq = ++monitorSeq;
        desktop.read("/monitor", {}, (d, e) => {
            if (seq !== monitorSeq || !online)
                return;
            if (e) {
                problem = e;
                return;
            }
            initialized = true;
            problem = "";
            const records = d.records || [];
            if (!U.sameData(rows, records))
                rows = records;
            const nextPending = d.pendingRequests || [];
            if (JSON.stringify(pending) !== JSON.stringify(nextPending))
                pending = nextPending;
        });
    }
    function refreshThread(subscribe) {
        if (!online || !currentId)
            return;
        const id = currentId, seq = ++detailSeq;
        const settingsRevision = modelSettingsRevision;
        if (subscribe)
            reading = true;
        desktop.read("/threads/" + encodeURIComponent(id), {
            subscribe: !!subscribe
        }, (d, e) => {
            if (seq !== detailSeq || currentId !== id)
                return;
            reading = false;
            if (e) {
                tell(e);
                return;
            }
            applyThreadDetail(id, d, settingsRevision, cwd);
        });
    }
    function applyThreadDetail(id, d, settingsRevision, fallbackCwd) {
        const nextThread = d.thread || {};
        if (historyExtended) {
            const ids = new Set((nextThread.turns || []).map(t => t.id));
            nextThread.turns = (thread.turns || []).filter(t => !ids.has(t.id)).concat(nextThread.turns || []);
        } else
            historyCursor = d.historyCursor || "";
        thread = nextThread;
        cwd = thread.cwd || fallbackCwd;
        if (d.pendingRequests) {
            const next = pending.filter(r => r.params.threadId !== id).concat(d.pendingRequests);
            if (!U.sameData(pending, next))
                pending = next;
        }
        if (thread.model && settingsRevision === modelSettingsRevision)
            activeModel = Object.assign({
                model: thread.model,
                reasoningEffort: thread.reasoningEffort || "",
                serviceTier: thread.serviceTier || "default"
            }, selectionSettings);
    }
    function older(done) {
        if (!historyCursor || loadingOlder || !online)
            return;
        const id = currentId, serial = selection;
        loadingOlder = true;
        desktop.read("/threads/" + encodeURIComponent(id) + "/history", {
            cursor: historyCursor
        }, (d, e) => {
            if (serial !== selection)
                return;
            loadingOlder = false;
            if (e) {
                tell(e);
                return;
            }
            const existing = thread.turns || [], ids = new Set(existing.map(t => t.id));
            historyExtended = true;
            historyCursor = d.nextCursor || "";
            thread = Object.assign({}, thread, {
                turns: (d.data || []).filter(t => !ids.has(t.id)).concat(existing)
            });
            if (done)
                done();
        });
    }
    function nav(p) {
        openingThreadId = "";
        drawer = false;
        page = p;
        if (p === "usage")
            loadUsage();
    }
    function overview(s) {
        scope = s;
        workspaceFilter = "";
        nav("overview");
    }
    function recordsFor(path) {
        workspaceFilter = path || "";
        nav("records");
        recordsView.load(false);
    }
    function showThreadMenu(source, position, summary) {
        if (!summary?.id)
            return;
        const point = source.mapToItem(threadMenu.parent, position.x, position.y);
        threadMenu.targetThread = summary;
        threadMenu.popup(point.x, point.y);
    }
    function applyThreadName(id, name) {
        ++monitorSeq;
        const rename = summary => Object.assign({}, summary, {name: name});
        rows = rows.map(record => record.thread.id === id ? Object.assign({}, record, {thread: rename(record.thread)}) : record);
        recordsView.threads = recordsView.threads.map(summary => summary.id === id ? rename(summary) : summary);
        if (currentId === id) {
            thread = rename(thread);
            refreshThread(false);
        }
    }
    function removeDeletedThreads(ids) {
        const removed = new Set(ids);
        ++monitorSeq;
        rows = rows.filter(record => !removed.has(record.thread.id));
        pending = pending.filter(request => !removed.has(request.params.threadId));
        if (removed.has(openingThreadId))
            openingThreadId = "";
        if (removed.has(currentId)) {
            ++selection;
            ++detailSeq;
            currentId = "";
            thread = {};
            reading = false;
            activeModel = {};
            selectionSettings = {};
            if (page === "chat")
                overview("任务总览");
        }
        for (const id of removed) {
            if (pins.includes(id))
                pin(id);
            delete drafts[id];
        }
    }
    function openThread(id) {
        if (!id || id === openingThreadId)
            return;
        if (id === currentId && page === "chat" && (reading || thread.turns)) {
            nav("chat");
            return;
        }
        const r = rows.find(x => x.thread.id === id);
        const summary = r ? r.thread : {id: id};
        if (!online) {
            showThread(id, {thread: summary}, summary.cwd || "");
            return;
        }
        const seq = ++openThreadSeq;
        openingThreadId = id;
        desktop.read("/threads/" + encodeURIComponent(id), {subscribe: true}, (d, e) => {
            if (openingThreadId !== id || seq !== openThreadSeq)
                return;
            if (e) {
                openingThreadId = "";
                tell(e);
                return;
            }
            showThread(id, d, summary.cwd || "");
        });
    }
    function showThread(id, detail, fallbackCwd) {
        ++selection;
        ++detailSeq;
        currentId = id;
        reading = false;
        activeModel = {};
        selectionSettings = {};
        tab = "对话";
        applyThreadDetail(id, detail, modelSettingsRevision, fallbackCwd);
        nav("chat");
    }
    function newThread(path) {
        if (!online) {
            nav("settings");
            return;
        }
        const folder = path || desktop.directory(cwd);
        if (!folder)
            return;
        ++selection;
        currentId = "";
        thread = {};
        cwd = folder;
        reading = false;
        tab = "对话";
        activeModel = {};
        selectionSettings = {};
        nav("chat");
    }
    function act(op, body, cb) {
        if (busy || !online)
            return;
        busy = true;
        desktop.act(op, body, (d, e) => {
            busy = false;
            if (e && !(op === "command" && d && d.externalWriter))
                tell(e);
            if (cb)
                cb((d || {}).result || {}, e, d || {});
            refreshMonitor();
        });
    }
    function loadUsage() {
        if (online)
            desktop.read("/usage", {}, (d, e) => {
                if (e)
                    tell(e);
                else
                    usage = d;
            });
    }
    function pin(id) {
        if (!id)
            return;
        pins = pins.includes(id) ? pins.filter(p => p !== id) : pins.concat([id]);
        desktop.save("workspace/pins", JSON.stringify(pins));
    }
    function models(cb, onFailure) {
        const id = currentId, serial = selection;
        const settingsRevision = modelSettingsRevision;
        desktop.read(id ? "/threads/" + encodeURIComponent(id) + "/model-settings" : "/models", {cwd: cwd}, (d, e) => {
            if (serial !== selection) {
                if (onFailure)
                    onFailure();
                return;
            }
            if (e) {
                tell(e);
                if (onFailure)
                    onFailure();
                return;
            }
            catalog = d.models || [];
            if (settingsRevision === modelSettingsRevision)
                activeModel = Object.assign({}, d.current || {}, selectionSettings);
            if (cb)
                cb();
        });
    }
    function modelSetting(command, value, onApplied, onSettled) {
        if (busy || !online || openingThreadId) return false;
        if (thread.archived) {
            tell("请先恢复这条已归档会话。");
            return false;
        }
        const key = ({
                model: "model",
                reasoning: "reasoningEffort",
                fast: "serviceTier"
            })[command];
        let next = Object.assign({}, activeModel);
        next[key] = value;
        const target = catalog.find(m => m.model === next.model);
        if (!target) { tell("模型目录已变化，请重新打开模型菜单。"); return false; }
        if (command === "model") {
            if (!(target.effortOptions || []).some(o => o.value === next.reasoningEffort))
                next.reasoningEffort = target.defaultReasoningEffort || target.defaultEffort || null;
            if (next.serviceTier !== "default" && !(target.serviceTiers || []).some(t => t.id === next.serviceTier))
                next.serviceTier = "default";
        }
        if (!currentId) {
            ++modelSettingsRevision;
            selectionSettings = next;
            activeModel = next;
            if (onApplied)
                onApplied();
            if (onSettled)
                onSettled();
            return true;
        }
        const duringTurn = (thread.turns || []).slice(-1)[0]?.status === "inProgress";
        const id = currentId, serial = selection;
        const args = {value: value};
        if (command === "model") {
            args.effort = next.reasoningEffort;
            args.serviceTier = next.serviceTier || "default";
        }
        act("command", {
            threadId: id,
            command: command,
            args: args
        }, (d, e, raw) => {
            if (currentId === id && selection === serial) {
                if (!e) {
                    ++modelSettingsRevision;
                    activeModel = Object.assign({}, next, d.modelSettings?.current);
                    blockedModelChoice = null;
                    if (duringTurn)
                        tell("已保存，下一轮生效。");
                    if (onApplied)
                        onApplied();
                } else if (raw.externalWriter) {
                    thread = Object.assign({}, thread, {externalWriter: true});
                    blockedModelChoice = {threadId: id, command: command, value: value, settings: next};
                    modelConflict.open();
                }
            }
            if (onSettled)
                onSettled();
        });
        return true;
    }
    function forkModelChoice() {
        const choice = blockedModelChoice;
        if (!choice || choice.threadId !== currentId) return;
        modelConflict.close();
        act("forkWithSettings", {
            threadId: choice.threadId,
            settings: {
                model: choice.settings.model,
                effort: choice.settings.reasoningEffort,
                serviceTier: choice.settings.serviceTier || "default"
            }
        }, (d, e) => {
            if (e || currentId !== choice.threadId) return;
            const draft = chatView.composer;
            drafts[d.threadId] = {text: draft.input.text, files: draft.attachments, refs: draft.references, mode: draft.mode};
            blockedModelChoice = null;
            openThread(d.threadId);
        });
    }
    Timer {
        id: liveUpdate
        interval: 90
        onTriggered: {
            const id = app.currentId;
            const selection = app.selection;
            if (!id || app.page !== "chat" || app.reading)
                return;
            desktop.read("/threads/" + encodeURIComponent(id) + "/live", {}, (d, e) => {
                if (e || app.selection !== selection || app.currentId !== id || !d.turn || !d.turn.id)
                    return;
                let turns = (app.thread.turns || []).slice(), i = turns.findIndex(t => t.id === d.turn.id);
                if (i < 0)
                    turns.push(d.turn);
                else {
                    const old = turns[i], items = (old.items || []).slice();
                    for (const next of d.turn.items || []) {
                        const j = items.findIndex(it => it.id === next.id);
                        if (j < 0)
                            items.push(next);
                        else
                            items[j] = next;
                    }
                    turns[i] = Object.assign({}, old, d.turn, {
                        items: items
                    });
                }
                app.thread = Object.assign({}, app.thread, {
                    turns: turns
                });
            });
        }
    }
    Timer {
        id: reload
        property string detailId: ""
        interval: 120
        onTriggered: {
            const refreshDetail = detailId && detailId === app.currentId;
            detailId = "";
            app.refreshMonitor();
            if (refreshDetail && app.page === "chat")
                app.refreshThread(false);
        }
    }
    Timer {
        interval: 10000
        repeat: true
        running: app.online
        onTriggered: app.refreshMonitor()
    }
    Connections {
        target: desktop
        function onAppearanceChanged() { Qt.callLater(app.syncWindowFrame); }
        function onLost() {
            app.online = false;
            app.connecting = false;
            app.openingThreadId = "";
            app.busy = false;
            app.problem = "已有 Codex App Server 已断开连接。";
        }
        function onEvent(method, params) {
            if (method.indexOf("item/") === 0) {
                if (params.threadId === app.currentId && !liveUpdate.running)
                    liveUpdate.start();
                return;
            }
            if (method === "account/updated" || method === "account/login/completed")
                app.refreshAccount();
            if (method.indexOf("thread/") === 0 || method.indexOf("turn/") === 0 || method === "request/changed" || (app.currentId && params.threadId === app.currentId)) {
                if (params.threadId === app.currentId)
                    reload.detailId = app.currentId;
                if (!reload.running)
                    reload.start();
            }
        }
    }
    Component.onCompleted: {
        syncWindowFrame();
        connectExisting();
    }
    Shortcut {
        sequence: "Ctrl+K"
        onActivated: search.open()
    }
    Shortcut {
        sequence: "Ctrl+N"
        onActivated: app.newThread("")
    }
    Shortcut {
        sequence: "Ctrl+,"
        onActivated: app.nav("settings")
    }
    Shortcut {
        sequence: "Ctrl+\\"
        onActivated: app.compact ? app.drawer = !app.drawer : app.collapsed = !app.collapsed
    }
    Sidebar {
        id: rail
        appRoot: app
        visible: app.compact ? app.drawer : !app.collapsed
        z: 3
        width: Math.min(272, app.width - 36)
        height: app.height
        onSearch: search.open()
    }
    Rectangle {
        visible: app.compact && app.drawer
        anchors.fill: parent
        z: 2
        color: "#55000000"
        TapHandler {
            onTapped: app.drawer = false
        }
    }
    Item {
        id: mainArea
        objectName: "mainArea"
        anchors {
            left: parent.left
            leftMargin: !app.compact && !app.collapsed ? rail.width : 0
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        Overview {
            anchors.fill: parent
            visible: app.page === "overview"
            appRoot: app
        }
        Chat {
            id: chatView
            anchors.fill: parent
            visible: app.page === "chat"
            appRoot: app
        }
        Preferences {
            anchors.fill: parent
            visible: app.page === "settings" || app.page === "usage"
            appRoot: app
        }
        Records {
            id: recordsView
            anchors.fill: parent
            visible: app.page === "records"
            appRoot: app
        }
        SamayaButton {
            visible: app.compact || (app.collapsed && app.page !== "chat")
            x: 4
            y: 6
            glyph: "menu"
            hint: "展开侧栏"
            onClicked: app.compact ? app.drawer = true : app.collapsed = false
        }
    }
    Search {
        id: search
        appRoot: app
        parent: Overlay.overlay
        anchors.centerIn: parent
    }
    SamayaMenu {
        id: threadMenu
        objectName: "threadContextMenu"
        parent: Overlay.overlay
        implicitWidth: 140
        property var targetThread: ({})
        SamayaMenuItem {
            objectName: "renameThreadAction"
            text: "重命名"
            enabled: app.online && !app.busy
            onTriggered: renameSheet.openFor(threadMenu.targetThread)
        }
        SamayaMenuItem {
            objectName: "deleteThreadAction"
            text: "删除"
            enabled: app.online && !app.busy
            onTriggered: recordsView.prepare("delete", [threadMenu.targetThread.id])
        }
    }
    Sheet {
        id: renameSheet
        objectName: "renameThreadSheet"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(420, app.width - 32)
        height: renameLayout.implicitHeight + topPadding + bottomPadding
        closePolicy: app.busy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property string threadId: ""
        property string originalName: ""
        function openFor(summary) {
            threadId = summary.id;
            originalName = U.title(summary);
            nameInput.text = originalName;
            open();
        }
        function saveName() {
            const name = nameInput.text.trim();
            if (!threadId || !name || name === originalName || !app.online || app.busy)
                return;
            const id = threadId;
            app.act("command", {threadId: id, command: "rename", args: {value: name}}, (_, error) => {
                if (!error) {
                    app.applyThreadName(id, name);
                    close();
                }
            });
        }
        onOpened: {
            nameInput.forceActiveFocus();
            nameInput.selectAll();
        }
        ColumnLayout {
            id: renameLayout
            anchors.fill: parent
            spacing: 12
            Ink {
                text: "重命名对话"
                font.pixelSize: 20
                font.weight: Font.Medium
            }
            Field {
                id: nameInput
                objectName: "threadNameInput"
                Layout.fillWidth: true
                placeholderText: "输入对话名称"
                Accessible.name: "对话名称"
                enabled: !app.busy
                onAccepted: renameSheet.saveName()
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                SamayaButton {
                    text: "取消"
                    enabled: !app.busy
                    onClicked: renameSheet.close()
                }
                SamayaButton {
                    kind: "primary"
                    text: "保存"
                    enabled: app.online && !app.busy && !!nameInput.text.trim()
                             && nameInput.text.trim() !== renameSheet.originalName
                    onClicked: renameSheet.saveName()
                }
            }
        }
    }
    Sheet {
        id: modelConflict
        objectName: "modelConflict"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(480, app.width - 32)
        height: conflictBody.implicitHeight + 32
        ColumnLayout {
            id: conflictBody
            anchors.fill: parent
            spacing: 12
            Ink {
                text: "这条会话正由另一 Codex 实例使用"
                font.pixelSize: 18
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            Ink {
                text: "释放占用后可以重试。也可以创建保留当前历史的副本，并把所选模型和速度应用到副本。"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Style.muted
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                SamayaButton { text: "取消"; onClicked: modelConflict.close() }
                SamayaButton {
                    text: "重试原会话"
                    enabled: !app.busy && !!app.blockedModelChoice && app.blockedModelChoice.threadId === app.currentId
                    onClicked: {
                        const choice = app.blockedModelChoice;
                        modelConflict.close();
                        app.modelSetting(choice.command, choice.value);
                    }
                }
                SamayaButton {
                    text: "在副本中应用"
                    kind: "primary"
                    enabled: !app.busy && !!app.blockedModelChoice && app.blockedModelChoice.threadId === app.currentId
                    onClicked: app.forkModelChoice()
                }
            }
        }
    }
    Sheet {
        id: photo
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(app.width - 32, 960)
        height: Math.min(app.height - 48, 720)
        onClosed: app.previewImage = ""
        Ink {
            text: "图片预览"
            font.pixelSize: 16
            anchors.left: parent.left
            anchors.top: parent.top
        }
        Image {
            anchors.fill: parent
            anchors.topMargin: 42
            source: app.previewImage
            fillMode: Image.PreserveAspectFit
        }
        SamayaButton {
            anchors.right: parent.right
            text: "关闭"
            onClicked: photo.close()
        }
    }
    onPreviewImageChanged: if (previewImage)
        photo.open()
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        width: Math.min(app.width - 24, msg.implicitWidth + 32)
        height: msg.implicitHeight + 16
        radius: 8
        color: Style.surface
        border.color: Style.border
        visible: !!app.notice
        z: 8
        Ink {
            id: msg
            anchors.centerIn: parent
            width: parent.width - 24
            text: app.notice
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
