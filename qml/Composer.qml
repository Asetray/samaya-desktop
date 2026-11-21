import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Rectangle {
    id: box
    required property var appRoot
    property alias input: editor
    property var attachments: []
    property var references: []
    property string mode: "默认"
    property var history: []
    property int historyIndex: -1
    property string scratch: ""
    property string draftKey: appRoot.currentId || ("new:" + appRoot.cwd)
    property string loadedKey: ""
    property string picker: ""
    property var choices: []
    property bool updating: false
    property int suggestionIndex: 0
    property var suggestions: []
    property int suggestSequence: 0
    property int tokenStart: 0
    property string dialogAction: ""
    property string dialogThread: ""
    property bool modelLoading: false
    property bool speedLoading: false
    property int modelSettingsSelection: -1
    readonly property bool canChangeModel: appRoot.online && !appRoot.busy && !appRoot.openingThreadId && !appRoot.thread.archived
    readonly property string modelLabel: appRoot.catalog.find(m => m.model === appRoot.activeModel.model)?.displayName
                                         || appRoot.activeModel.model || "选择模型"
    readonly property var commands: [
        {
            label: "/model",
            detail: "选择模型",
            action: "models"
        },
        {
            label: "/permissions",
            detail: "权限范围",
            action: "permissions",
            requiresThread: true
        },
        {
            label: "/goal",
            detail: "持续目标",
            action: "goal",
            requiresThread: true
        },
        {
            label: "/review",
            detail: "原生代码审查",
            action: "review",
            requiresThread: true
        },
        {
            label: "/cloud",
            detail: "当前连接未运行云接口 · 不可用",
            disabled: true
        },
        {
            label: "/plan",
            detail: "计划模式",
            action: "plan"
        },
        {
            label: "/status",
            detail: "使用情况",
            action: "usage"
        }
    ]
    function suggest() {
        const left = editor.text.slice(0, editor.cursorPosition), seq = ++suggestSequence;
        suggestions = [];
        suggestionIndex = 0;
        if (!editor.activeFocus || updating || left.split("```").length % 2 === 0 || left.split("\n").pop().split("`").length % 2 === 0)
            return;
        const match = /(?:^|\s)([$@])([^\s$@]*)$/.exec(left), slash = /(?:^|\n)\/(\w*)$/.exec(left);
        if (slash) {
            tokenStart = left.length - slash[1].length - 1;
            suggestions = commands.filter(c => c.label.indexOf("/" + slash[1]) === 0);
            return;
        }
        if (!match || !appRoot.online)
            return;
        tokenStart = left.length - match[2].length - 1;
        const get = (route, kind) => desktop.read(route, {
                cwd: appRoot.cwd
            }, (d, e) => {
                if (seq !== suggestSequence || e || !editor.activeFocus)
                    return;
                const list = kind === "技能" ? (d.data || []).reduce((a, g) => a.concat(g.skills || []), []) : d.data || [];
                suggestions = suggestions.concat(list.filter(x => x.enabled !== false && (x.displayName || x.name || x.id).toLowerCase().indexOf(match[2].toLowerCase()) >= 0).map(x => ({
                            label: x.displayName || x.name || x.id,
                            detail: x.description || "",
                            kind: kind,
                            ref: kind === "技能" ? {
                                type: "skill",
                                name: x.name,
                                path: x.path
                            } : {
                                type: "mention",
                                name: x.name || x.id,
                                path: "app://" + x.id
                            }
                        }))).slice(0, 50);
            });
        if (match[1] === "$")
            get("/skills", "技能");
        get("/apps", "应用");
    }
    function pickSuggestion(i) {
        const item = suggestions[i];
        if (!item || item.disabled || item.requiresThread && !appRoot.currentId)
            return;
        const end = editor.cursorPosition;
        editor.remove(tokenStart, end);
        suggestions = [];
        ++suggestSequence;
        choose(item);
    }
    function commandDialog(action) {
        dialogAction = action;
        dialogThread = appRoot.currentId;
        commandValue.text = "";
        if (!dialogThread)
            return;
        if (action === "permissions") {
            desktop.read("/permissions", {
                cwd: appRoot.cwd
            }, (d, e) => {
                if (dialogThread !== appRoot.currentId)
                    return;
                if (e)
                    appRoot.tell(e);
                else
                    showMenu("权限范围", (d.data || []).map(p => ({
                                label: p.id,
                                disabled: !p.allowed,
                                action: "permissionChoice",
                                value: p.id
                            })));
            });
            return;
        }
        commandSheet.open();
        if (action === "goal")
            desktop.read("/threads/" + encodeURIComponent(dialogThread) + "/goal", {}, (d, e) => {
                if (!e && commandSheet.opened && !commandValue.text)
                    commandValue.text = (d.goal || {}).objective || "";
            });
    }
    readonly property var turns: appRoot.thread.turns || []
    readonly property var last: turns.length ? turns[turns.length - 1] : ({})
    readonly property bool running: last.status === "inProgress"
    readonly property bool hasDraft: !!editor.text.trim() || attachments.length > 0 || references.length > 0
    readonly property bool stopMode: running && !hasDraft
    implicitHeight: layout.implicitHeight + 26
    radius: 24
    color: Style.surface
    border.color: drop.containsDrag ? Style.accent : Style.border
    function restoreDraft() {
        if (loadedKey === draftKey)
            return;
        if (loadedKey)
            appRoot.drafts[loadedKey] = {
                text: editor.text,
                files: attachments,
                refs: references,
                mode: mode
            };
        const d = appRoot.drafts[draftKey] || {};
        updating = true;
        editor.text = d.text || "";
        attachments = d.files || [];
        references = d.refs || [];
        mode = d.mode || "默认";
        loadedKey = draftKey;
        historyIndex = -1;
        updating = false;
    }
    onDraftKeyChanged: {
        if (editor)
            restoreDraft();
        else
            Qt.callLater(restoreDraft);
    }
    function attach(value) {
        if (value && value.name)
            attachments = attachments.concat([value]);
        else
            appRoot.tell("无法读取附件或图片过大。");
    }
    function chooseFiles() {
        for (let path of desktop.files())
            attach(desktop.attachment(path));
    }
    function showMenu(name, items) {
        picker = name;
        choices = items;
        if (!popup.opened) popup.open();
    }
    function models(showList) {
        if (modelMenu.opened) {
            if (showList)
                modelMenu.showList();
            else
                modelMenu.close();
            return;
        }
        withModelSettings(() => {
            modelMenu.listOpen = showList;
            modelMenu.open();
            speedMenu.close();
        });
    }
    function withModelSettings(show) {
        if (modelLoading || speedLoading || !canChangeModel)
            return;
        modelLoading = true;
        appRoot.models(() => {
            modelSettingsSelection = appRoot.selection;
            modelLoading = false;
            if (visible && canChangeModel)
                show();
        }, () => modelLoading = false);
    }
    function toggleSpeedMenu(origin) {
        if (speedMenu.visible) {
            speedMenu.close();
            return;
        }
        if (speedLoading || modelLoading || !canChangeModel)
            return;
        const selection = appRoot.selection;
        const show = () => {
            if (!visible || selection !== appRoot.selection || !canChangeModel)
                return;
            speedMenu.returnFocus = origin;
            speedMenu.open();
            modelMenu.close();
        };
        if (modelSettingsSelection === selection && appRoot.catalog.some(model => model.model === appRoot.activeModel.model)) {
            show();
            return;
        }
        speedLoading = true;
        appRoot.models(() => {
            speedLoading = false;
            if (selection === appRoot.selection)
                modelSettingsSelection = selection;
            show();
        }, () => speedLoading = false);
    }
    Connections {
        target: appRoot
        function onOnlineChanged() {
            if (!appRoot.online)
                box.modelSettingsSelection = -1;
        }
    }
    function catalog(type) {
        const context = appRoot.selection;
        desktop.read(type === "技能" ? "/skills" : "/apps", {
            cwd: appRoot.cwd
        }, (d, e) => {
            if (context !== appRoot.selection)
                return;
            if (e) {
                appRoot.tell(e);
                return;
            }
            let list = type === "技能" ? (d.data || []).reduce((a, g) => a.concat(g.skills || []), []) : d.data || [];
            showMenu(type, list.filter(x => x.enabled !== false).map(x => ({
                        label: x.displayName || x.name || x.id,
                        ref: type === "技能" ? {
                            type: "skill",
                            name: x.name,
                            path: x.path
                        } : {
                            type: "mention",
                            name: x.name || x.id,
                            path: "app://" + x.id
                        }
                    })));
        });
    }
    function choose(item) {
        popup.close();
        if (item.ref) {
            references = references.concat([item.ref]);
            editor.forceActiveFocus();
            return;
        }
        if (item.action === "files") {
            chooseFiles();
            return;
        }
        if (item.action === "skills" || item.action === "apps") {
            catalog(item.action === "skills" ? "技能" : "应用");
            return;
        }
        if (item.action === "commands") {
            showMenu("命令", commands);
            return;
        }
        if (["permissions", "goal", "review"].includes(item.action)) {
            commandDialog(item.action);
            return;
        }
        if (item.action === "permissionChoice") {
            appRoot.act("permission", {
                threadId: dialogThread,
                value: item.value
            });
            return;
        }
        if (item.action === "models") {
            models(true);
            return;
        }
        if (item.action === "plan") {
            mode = "计划";
            return;
        }
        if (item.action === "usage") {
            appRoot.nav("usage");
            return;
        }
        if (picker === "模式") {
            mode = item.value;
        }
    }
    function send() {
        if (!appRoot.online || appRoot.busy || appRoot.openingThreadId || appRoot.thread.archived)
            return;
        if (!hasDraft) {
            if (running)
                appRoot.act("interrupt", {
                    threadId: appRoot.currentId,
                    turnId: last.id
                }, () => appRoot.refreshThread(false));
            return;
        }
        const input = editor.text.trim();
        if (input.startsWith("/")) {
            const cmd = commands.find(c => c.label === input.split(/\s+/)[0]);
            if (cmd) {
                if (cmd.disabled || cmd.requiresThread && !appRoot.currentId) {
                    appRoot.tell("当前会话无法使用此命令。");
                    return;
                }
                editor.clear();
                choose(cmd);
                return;
            }
        }
        const model = appRoot.activeModel.model;
        if (mode === "计划" && !model) {
            appRoot.models(() => {
                if (appRoot.activeModel.model)
                    send();
                else
                    appRoot.tell("请选择可用的模型。");
            });
            return;
        }
        let settings = {};
        if (appRoot.selectionSettings.model)
            settings.model = appRoot.selectionSettings.model;
        if (appRoot.selectionSettings.reasoningEffort)
            settings.effort = appRoot.selectionSettings.reasoningEffort;
        if (appRoot.selectionSettings.serviceTier)
            settings.serviceTier = appRoot.selectionSettings.serviceTier;
        if (model)
            settings.collaborationMode = {
                mode: mode === "计划" ? "plan" : "default",
                settings: {
                    model: model,
                    reasoning_effort: appRoot.activeModel.reasoningEffort || null,
                    developer_instructions: null
                }
            };
        let payload = {
            text: editor.text,
            files: attachments.filter(a => a.id),
            images: attachments.filter(a => a.url),
            references: references,
            settings: settings,
            expectedTurnId: last.id || null
        };
        const origin = loadedKey, seq = appRoot.selection, steer = running;
        function deliver(id) {
            payload.threadId = id;
            const shell = input.startsWith("!") && !steer;
            if (shell)
                payload.command = input.slice(1).trim();
            appRoot.act(shell ? "shell" : steer ? "steer" : "send", payload, (d, e) => {
                if (e)
                    return;
                delete appRoot.drafts[origin];
                if (appRoot.selection === seq && appRoot.currentId === id) {
                    history = history.concat([payload.text]).slice(-100);
                    historyIndex = -1;
                    editor.clear();
                    attachments = [];
                    references = [];
                    appRoot.refreshThread(false);
                }
            });
        }
        if (appRoot.currentId)
            deliver(appRoot.currentId);
        else
            appRoot.act("create", {
                cwd: appRoot.cwd,
                model: model || "",
                settings: settings
            }, (d, e) => {
                if (e || appRoot.selection !== seq)
                    return;
                const id = d.threadId;
                // The draft belongs to the new thread even when the first turn fails.
                loadedKey = id;
                appRoot.currentId = id;
                appRoot.thread = {
                    id: id,
                    cwd: appRoot.cwd,
                    turns: []
                };
                appRoot.refreshThread(true);
                deliver(id);
            });
    }
    DropArea {
        id: drop
        anchors.fill: parent
        onDropped: d => {
            for (let url of d.urls)
                box.attach(desktop.attachment(url));
        }
    }
    ColumnLayout {
        id: layout
        x: 17
        y: 13
        width: parent.width - 34
        spacing: 8
        Flow {
            id: attachmentFlow
            visible: box.attachments.length + box.references.length > 0
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: box.attachments
                delegate: RowLayout {
                    required property var modelData
                    required property int index
                    width: Math.min(implicitWidth, attachmentFlow.width)
                    height: 40
                    spacing: 8
                    Image {
                        visible: !!modelData.url
                        source: modelData.url || ""
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        fillMode: Image.PreserveAspectCrop
                        TapHandler {
                            onTapped: appRoot.previewImage = parent.source
                        }
                    }
                    Ink {
                        text: modelData.name
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.min(implicitWidth, 180)
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignVCenter
                    }
                    SamayaButton {
                        glyph: "search-close"
                        hint: "移除附件"
                        implicitHeight: 32
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: box.attachments = box.attachments.filter((_, i) => i !== index)
                    }
                }
            }
            Repeater {
                model: box.references
                SamayaButton {
                    required property var modelData
                    required property int index
                    text: modelData.name + " ×"
                    onClicked: box.references = box.references.filter((_, i) => i !== index)
                }
            }
        }
        ScrollView {
            objectName: "composerTextArea"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(168, Math.max(appRoot.compact ? 40 : 48, editor.implicitHeight))
            contentWidth: availableWidth
            clip: true
            TextArea {
                id: editor
                objectName: "composer"
                placeholderText: !appRoot.online ? "等待连接恢复…" : box.running ? "追加当前指令…" : appRoot.currentId ? "发送消息…" : "在 " + U.base(appRoot.cwd) + " 中发送消息…"
                color: Style.ink
                placeholderTextColor: Style.muted
                selectionColor: Style.textSelection
                font.family: Style.family
                font.pixelSize: 16
                padding: 0
                leftPadding: 8
                topPadding: 4
                rightPadding: 12
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                background: null
                onTextChanged: suggestDelay.restart()
                onCursorPositionChanged: suggestDelay.restart()
                Keys.onPressed: event => {
                    if (inputMethodComposing)
                        return;
                    if (box.suggestions.length) {
                        if (event.key === Qt.Key_Escape) {
                            box.suggestions = [];
                            event.accepted = true;
                            return;
                        }
                        if ([Qt.Key_Up, Qt.Key_Down].includes(event.key)) {
                            box.suggestionIndex = (box.suggestionIndex + (event.key === Qt.Key_Up ? -1 : 1) + box.suggestions.length) % box.suggestions.length;
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Tab) {
                            event.accepted = true;
                            box.pickSuggestion(box.suggestionIndex);
                            return;
                        }
                    }
                    if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                        event.accepted = true;
                        box.send();
                    } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                        let img = desktop.clipboardImage();
                        if (img.name) {
                            box.attach(img);
                            event.accepted = true;
                        }
                    } else if (event.key === Qt.Key_Up && cursorPosition === 0 && box.history.length) {
                        if (box.historyIndex < 0) {
                            box.scratch = text;
                            box.historyIndex = box.history.length;
                        }
                        box.historyIndex = Math.max(0, box.historyIndex - 1);
                        text = box.history[box.historyIndex];
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down && box.historyIndex >= 0 && cursorPosition === length) {
                        box.historyIndex++;
                        if (box.historyIndex >= box.history.length) {
                            text = box.scratch;
                            box.historyIndex = -1;
                        } else
                            text = box.history[box.historyIndex];
                        event.accepted = true;
                    }
                }
            }
        }
        RowLayout {
            id: toolbar
            objectName: "composerToolbar"
            readonly property int buttonHeight: 36
            Layout.fillWidth: true
            Layout.preferredHeight: toolbar.buttonHeight
            spacing: 8
            SamayaButton {
                id: addButton
                glyph: "plus"
                hint: "添加"
                implicitWidth: 36
                glyphSize: 18
                onClicked: box.showMenu("添加", [
                    {
                        label: "添加文件",
                        action: "files"
                    },
                    {
                        label: "技能",
                        action: "skills"
                    },
                    {
                        label: "应用",
                        action: "apps"
                    },
                    {
                        label: "命令",
                        action: "commands"
                    }
                ])
            }
            Item {
                Layout.fillWidth: true
            }
            RowLayout {
                id: modelControls
                spacing: appRoot.compact ? 8 : 2
                readonly property real compactModelWidth: Math.max(0, layout.width - addButton.implicitWidth
                    - modeSelector.implicitWidth - sendButton.implicitWidth - 3 * toolbar.spacing - spacing)
                SamayaButton {
                    id: modeSelector
                    objectName: "modeSelector"
                    text: box.mode
                    typeSize: 13
                    implicitHeight: toolbar.buttonHeight
                    implicitWidth: 46
                    contentItem: Ink {
                        text: modeSelector.text
                        font.pixelSize: modeSelector.typeSize
                        horizontalAlignment: Text.AlignHCenter
                    }
                    onClicked: box.showMenu("模式", [
                        {label: "默认", value: "默认"},
                        {label: "计划", value: "计划"}
                    ])
                }
                ResponseSpeedButton {
                    id: fastSelector
                    objectName: "composerSpeedSelector"
                    visible: !appRoot.compact
                    implicitWidth: toolbar.buttonHeight
                    implicitHeight: toolbar.buttonHeight
                    serviceTier: appRoot.activeModel.serviceTier || "default"
                    enabled: box.canChangeModel && !box.modelLoading
                    opacity: appRoot.online && !appRoot.thread.archived ? 1 : 0.45
                    fill: speedMenu.visible || box.speedLoading || down ? Style.selected : hovered ? Style.hover : "transparent"
                    onClicked: box.toggleSpeedMenu(fastSelector)
                }
                SamayaButton {
                    id: modelSelector
                    objectName: "modelSelector"
                    implicitWidth: appRoot.compact ? Math.min(modelParts.implicitWidth + 8, modelControls.compactModelWidth)
                                                   : modelParts.implicitWidth + 20
                    implicitHeight: toolbar.buttonHeight
                    text: box.modelLabel + (effortText.text ? " " + effortText.text : "")
                    enabled: box.canChangeModel
                    opacity: appRoot.online && !appRoot.thread.archived ? 1 : 0.45
                    hint: modelMenu.visible || speedMenu.visible ? "" : text
                    fill: modelMenu.visible || down ? Style.selected : enabled && hovered ? Style.hover : "transparent"
                    contentItem: Item {
                        RowLayout {
                            id: modelParts
                            spacing: appRoot.compact ? 4 : 6
                            anchors.fill: parent
                            anchors.leftMargin: appRoot.compact ? 4 : 8
                            anchors.rightMargin: appRoot.compact ? 4 : 12
                            Image {
                                visible: box.modelLoading
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 16
                                fillMode: Image.PreserveAspectFit
                                source: visible ? Style.symbol("model-spinner", Style.ink) : ""
                                RotationAnimation on rotation {
                                    running: box.modelLoading && !desktop.reducedMotion
                                    from: 0
                                    to: 360
                                    duration: 800
                                    loops: Animation.Infinite
                                }
                            }
                            Ink {
                                text: box.modelLabel
                                font.pixelSize: 13
                                Layout.fillWidth: appRoot.compact
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: Math.min(implicitWidth, 160)
                                Layout.preferredHeight: 20
                            }
                            Ink {
                                id: effortText
                                visible: text.length > 0
                                text: U.effortLabel(modelMenu.displayEffort)
                                font.pixelSize: 13
                                color: Style.muted
                                Layout.preferredHeight: 20
                            }
                            Image {
                                Layout.preferredWidth: 9
                                Layout.preferredHeight: 6
                                source: Style.symbol("model-chevron", Style.muted)
                            }
                        }
                    }
                    onClicked: box.models(false)
                }
            }
            SamayaButton {
                id: sendButton
                objectName: "send"
                glyph: box.stopMode ? "composer-stop" : "arrow"
                hint: box.stopMode ? "停止本轮" : box.running ? "追加指令" : "发送消息"
                kind: "primary"
                implicitWidth: 36
                glyphSize: 18
                opacity: enabled ? 1 : 0.35
                enabled: appRoot.online && !appRoot.busy && !appRoot.thread.archived && (box.stopMode || box.hasDraft)
                onClicked: box.send()
                background: Rectangle {
                    radius: 18
                    color: parent.fill
                }
            }
        }
    }
    Timer {
        id: suggestDelay
        interval: 70
        onTriggered: box.suggest()
    }
    Rectangle {
        id: completion
        z: 4
        width: box.width
        height: Math.min(218, list.contentHeight + 12)
        anchors.bottom: parent.top
        anchors.bottomMargin: 6
        visible: box.suggestions.length > 0 && !popup.visible && editor.activeFocus
        color: Style.surface
        radius: 10
        border.color: Style.border
        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            model: box.suggestions
            currentIndex: box.suggestionIndex
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: 32
                radius: 5
                color: index === box.suggestionIndex ? Style.hover : "transparent"
                opacity: modelData.disabled || modelData.requiresThread && !appRoot.currentId ? 0.5 : 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    Ink {
                        text: modelData.label
                    }
                    Ink {
                        Layout.fillWidth: true
                        text: modelData.detail || ""
                        color: Style.muted
                        font.pixelSize: 12
                    }
                    Ink {
                        text: modelData.kind || "内置命令"
                        font.pixelSize: 12
                        color: Style.quiet
                    }
                }
                TapHandler {
                    onTapped: box.pickSuggestion(index)
                }
            }
        }
    }
    Sheet {
        id: commandSheet
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(480, appRoot.width - 32)
        height: 210
        ColumnLayout {
            anchors.fill: parent
            Ink {
                font.pixelSize: 18
                text: box.dialogAction === "goal" ? "持续目标" : "原生代码审查"
            }
            Ink {
                visible: box.dialogAction === "review"
                text: "审查当前工作区未提交的改动。"
            }
            Field {
                id: commandValue
                Layout.fillWidth: true
                visible: box.dialogAction === "goal"
                placeholderText: "目标"
            }
            Item {
                Layout.fillHeight: true
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                SamayaButton {
                    text: "取消"
                    onClicked: commandSheet.close()
                }
                SamayaButton {
                    kind: "primary"
                    text: "确认"
                    enabled: box.dialogThread === appRoot.currentId && (box.dialogAction !== "goal" || !!commandValue.text.trim())
                    onClicked: {
                        commandSheet.close();
                        appRoot.act(box.dialogAction, {
                            threadId: box.dialogThread,
                            value: commandValue.text
                        }, () => appRoot.refreshThread(false));
                    }
                }
            }
        }
    }
    ModelMenu {
        id: modelMenu
        objectName: "modelMenu"
        appRoot: box.appRoot
        editable: box.canChangeModel
        modelLabel: box.modelLabel
        width: Math.min(260, box.width)
        x: Math.max(0, layout.x + toolbar.x + modelControls.x + modelSelector.x + modelSelector.width - width)
        y: layout.y + toolbar.y + modelControls.y + modelSelector.y - height - 8
        onSpeedRequested: box.toggleSpeedMenu(modelSelector)
        onClosed: if (!speedMenu.visible) modelSelector.forceActiveFocus(Qt.OtherFocusReason)
    }
    SpeedMenu {
        id: speedMenu
        property Item returnFocus: modelSelector
        objectName: "speedMenu"
        appRoot: box.appRoot
        editable: box.canChangeModel
        parent: appRoot.compact ? modelSelector : fastSelector
        width: Math.min(262, box.width)
        margins: 8
        x: parent.width - width
        y: -height - 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        onChosen: value => appRoot.modelSetting("fast", value)
        onClosed: if (!modelMenu.visible) returnFocus.forceActiveFocus(Qt.OtherFocusReason)
    }
    Sheet {
        id: popup
        width: Math.min(box.width, 260)
        padding: 8
        modal: false
        x: box.picker === "添加" ? 0 : Math.max(0, box.width - width - 32)
        y: -height - 6
        height: Math.min(box.appRoot.height * 0.6, 52 + Math.max(1, box.choices.length) * 36)
        contentItem: Flickable {
            contentHeight: items.implicitHeight
            clip: true
            Column {
                id: items
                width: parent.width
                Ink {
                    text: box.picker
                    color: Style.muted
                    font.pixelSize: 12
                    padding: 8
                }
                Repeater {
                    model: box.choices
                    delegate: SamayaButton {
                        required property var modelData
                        width: items.width
                        alignLeft: true
                        selected: box.picker === "模式" && modelData.value === box.mode
                        enabled: !appRoot.busy && !modelData.disabled && (!modelData.requiresThread || !!appRoot.currentId)
                        text: modelData.label + (selected ? " ✓" : "")
                        onClicked: box.choose(modelData)
                    }
                }
                Ink {
                    visible: !box.choices.length
                    text: "暂无可用项目"
                    padding: 6
                    color: Style.muted
                }
            }
        }
    }
}
