import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: card
    required property var request
    required property var appRoot
    property var p: request.params || {}
    property var answers: ({})
    property bool questions: request.method === "item/tool/requestUserInput"
    property bool permissions: request.method === "item/permissions/requestApproval"
    property bool details: false
    implicitHeight: body.implicitHeight + 40
    color: Style.subtle
    radius: questions ? 8 : 0
    BreathingBorder {
        anchors.fill: parent
        visible: card.questions
    }
    Rectangle {
        visible: !card.questions
        width: 3
        height: parent.height
        color: Style.accent
    }
    function respond(result) {
        appRoot.act("respond", {
            threadId: p.threadId,
            requestKey: request.key,
            response: result
        }, () => appRoot.refreshThread(false));
    }
    ColumnLayout {
        id: body
        x: 24
        y: 18
        width: parent.width - 48
        spacing: 10
        Ink {
            visible: !card.questions
            text: "等待审批"
            font.pixelSize: 20
            font.weight: Font.Medium
        }
        Ink {
            Layout.fillWidth: true
            visible: !!text
            text: card.p.reason || card.p.command || card.p.grantRoot || ""
            wrapMode: Text.Wrap
        }
        Ink {
            Layout.fillWidth: true
            visible: !!card.p.reason && !!card.p.command
            text: card.p.command || ""
            wrapMode: Text.Wrap
        }
        Ink {
            Layout.fillWidth: true
            visible: !!text
            text: card.p.cwd || ""
            color: Style.muted
            font.pixelSize: 12
        }
        SamayaButton {
            visible: !card.questions && (card.permissions || !!card.p.proposedExecpolicyAmendment)
            text: card.details ? "收起详情" : "查看请求详情"
            onClicked: card.details = !card.details
        }
        Ink {
            visible: card.details
            Layout.fillWidth: true
            text: JSON.stringify(card.p, null, 2)
            font.family: "Cascadia Mono"
            wrapMode: Text.Wrap
        }
        Repeater {
            model: card.p.questions || []
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Ink {
                    text: modelData.question
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: modelData.options || []
                        delegate: SamayaButton {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: modelData.description ? 54 : 32
                            alignLeft: true
                            Accessible.name: modelData.label
                            onClicked: answer.text = modelData.label
                            contentItem: RowLayout {
                                spacing: 10
                                Image {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    source: Style.symbol(answer.text === modelData.label ? "decision-check" : "decision-circle", Style.accent)
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Ink {
                                        text: modelData.label
                                        Layout.fillWidth: true
                                    }
                                    Ink {
                                        visible: !!modelData.description
                                        font.pixelSize: 12
                                        color: Style.muted
                                        text: modelData.description || ""
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }
                }
                Field {
                    id: answer
                    visible: !(modelData.options || []).length || !!modelData.isOther
                    Layout.fillWidth: true
                    placeholderText: "输入回答"
                    echoMode: modelData.isSecret ? TextInput.Password : TextInput.Normal
                    onTextChanged: {
                        let a = Object.assign({}, card.answers);
                        a[modelData.id] = {
                            answers: [text]
                        };
                        card.answers = a;
                    }
                }
            }
        }
        SamayaButton {
            visible: card.questions
            kind: "quiet"
            text: "确认 →"
            enabled: !appRoot.busy && (card.p.questions || []).every(q => ((card.answers[q.id] || {}).answers || [""])[0].trim())
            onClicked: card.respond({
                answers: card.answers
            })
        }
        Flow {
            visible: !card.questions
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: card.questions ? [] : (card.p.availableDecisions || ["accept", "decline"])
                delegate: SamayaButton {
                    required property var modelData
                    visible: typeof modelData === "string" && ["accept", "acceptForSession", "decline", "cancel"].includes(modelData)
                    kind: modelData === "accept" ? "primary" : "outline"
                    text: ({
                            accept: "允许本次",
                            acceptForSession: "允许本会话",
                            decline: "拒绝",
                            cancel: "取消本次操作"
                        })[modelData] || ""
                    enabled: !appRoot.busy
                    onClicked: card.respond(card.permissions ? {
                        permissions: modelData === "accept" ? card.p.permissions : {},
                        scope: "turn"
                    } : {
                        decision: modelData
                    })
                }
            }
        }
    }
}
