import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Flickable {
    id: view
    required property var appRoot
    property bool detail: false
    readonly property bool usagePage: appRoot.page === "usage"
    readonly property var limits: appRoot.usage.rateLimits || Object.values(appRoot.usage.rateLimitsByLimitId || {})[0] || ({})
    readonly property var windows: [limits.primary, limits.secondary].filter(x => !!x)
    readonly property string manageUrl: "https://chatgpt.com/codex/cloud/settings/usage"
    clip: true
    contentWidth: width
    contentHeight: body.y + body.implicitHeight + 40
    ScrollBar.vertical: ScrollBar {}
    onUsagePageChanged: contentY = 0
    ColumnLayout {
        id: body
        x: (view.width - width) / 2
        y: appRoot.compact ? 52 : view.usagePage ? 44 : 64
        width: Math.min(720, view.width - (appRoot.compact ? 32 : 72))
        spacing: 18
        RowLayout {
            Layout.fillWidth: true
            Ink {
                Layout.fillWidth: true
                text: view.usagePage ? "使用情况" : "设置与连接"
                font.pixelSize: 24
                font.weight: Font.Medium
            }
            SamayaButton {
                visible: view.usagePage
                text: "刷新"
                onClicked: appRoot.loadUsage()
            }
        }
        ColumnLayout {
            visible: !view.usagePage
            Layout.fillWidth: true
            spacing: 16
            Ink {
                text: "管理界面外观和连接状态"
                color: Style.muted
                Layout.topMargin: 16
            }
            Ink {
                text: "界面外观"
                font.pixelSize: 18
                font.weight: Font.Medium
                Layout.topMargin: 16
            }
            RowLayout {
                Layout.fillWidth: true
                Ink {
                    text: "主题"
                    Layout.fillWidth: true
                }
                Repeater {
                    model: ["白垣", "苍渊"]
                    delegate: SamayaButton {
                        required property int index
                        required property string modelData
                        selected: index === (Style.dark ? 1 : 0)
                        text: modelData + (selected ? " ✓" : "")
                        implicitWidth: appRoot.compact ? 68 : 96
                        fill: selected ? Style.selected : Style.subtle
                        onClicked: {
                            appRoot.appearance = index + 1;
                            desktop.save("appearance/theme", index + 1);
                        }
                    }
                }
            }
            Ink {
                text: "主题偏好保存在此设备"
                font.pixelSize: 12
                color: Style.quiet
            }
            Ink {
                text: "连接"
                font.pixelSize: 18
                font.weight: Font.Medium
                Layout.topMargin: 24
            }
            Ink {
                text: appRoot.online ? "已连接 Codex" : appRoot.connecting ? "正在连接 Codex" : "连接已断开"
                color: Style.muted
            }
            SamayaButton {
                text: "连接详情与数据边界  " + (view.detail ? "⌄" : "›")
                onClicked: view.detail = !view.detail
            }
            Ink {
                visible: view.detail || !appRoot.online
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Style.muted
                text: appRoot.problem || "连接本机已有的 Codex App Server。会话、账户和审批由该实例管理。"
            }
            SamayaButton {
                visible: !appRoot.online
                text: "重新连接"
                kind: "outline"
                enabled: !appRoot.connecting
                onClicked: appRoot.connectExisting()
            }
            SamayaButton {
                visible: appRoot.online && appRoot.loginNeeded
                text: "登录已有 Codex 实例"
                kind: "outline"
                onClicked: desktop.login((d, e) => appRoot.tell(e || "请在浏览器中完成登录。"))
            }
            Ink {
                text: "使用情况"
                font.pixelSize: 18
                font.weight: Font.Medium
                Layout.topMargin: 28
            }
            RowLayout {
                Layout.fillWidth: true
                Ink {
                    text: "查看套餐、剩余额度和重置时间"
                    color: Style.muted
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                SamayaButton {
                    text: "查看使用情况 →"
                    onClicked: appRoot.nav("usage")
                }
            }
        }
        ColumnLayout {
            visible: view.usagePage
            Layout.fillWidth: true
            spacing: 16
            Row {
                SamayaButton {
                    text: "总览"
                    selected: true
                }
                SamayaButton {
                    text: "账户管理 ↗"
                    onClicked: Qt.openUrlExternally(view.manageUrl)
                }
            }
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Style.border
            }
            Ink {
                text: "当前套餐"
                font.pixelSize: 18
                Layout.topMargin: 10
            }
            RowLayout {
                Layout.fillWidth: true
                Ink {
                    Layout.fillWidth: true
                    text: (view.limits.planType || appRoot.account.planType || "尚未取得") + " 套餐"
                }
                SamayaButton {
                    text: "管理套餐 ↗"
                    onClicked: Qt.openUrlExternally(view.manageUrl)
                }
            }
            Ink {
                text: "订阅通过 ChatGPT 管理"
                font.pixelSize: 12
                color: Style.muted
            }
            Ink {
                text: "用量限制"
                font.pixelSize: 18
                Layout.topMargin: 24
            }
            Repeater {
                model: view.windows
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    readonly property int remaining: Math.max(0, Math.min(100, 100 - modelData.usedPercent))
                    RowLayout {
                        Layout.fillWidth: true
                        Ink {
                            Layout.fillWidth: true
                            text: modelData.windowDurationMins === 10080 ? "每周额度" : modelData.windowDurationMins ? modelData.windowDurationMins / 60 + " 小时额度" : "额度窗口"
                        }
                        Ink {
                            text: "剩余 " + remaining + "%"
                            color: Style.muted
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: Style.subtle
                        Rectangle {
                            width: parent.width * remaining / 100
                            height: 6
                            radius: 3
                            color: Style.ink
                        }
                    }
                    Ink {
                        text: modelData.resetsAt ? U.date(modelData.resetsAt) + " 重置" : ""
                        color: Style.muted
                        font.pixelSize: 12
                        Layout.bottomMargin: 16
                    }
                }
            }
            Ink {
                visible: !view.windows.length
                text: "暂无用量数据"
                color: Style.muted
            }
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Style.border
            }
            Ink {
                text: "额度余额"
                font.pixelSize: 18
                Layout.topMargin: 8
            }
            RowLayout {
                Layout.fillWidth: true
                Ink {
                    Layout.fillWidth: true
                    text: view.limits.credits ? (view.limits.credits.unlimited ? "不限额" : view.limits.credits.balance || "0") + " credits" : "暂无余额数据"
                }
                SamayaButton {
                    text: "管理额度 ↗"
                    onClicked: Qt.openUrlExternally(view.manageUrl)
                }
            }
            Ink {
                text: "购买额度和自动充值设置在账户管理中完成"
                font.pixelSize: 12
                color: Style.muted
            }
            Ink {
                text: "额度重置"
                font.pixelSize: 18
                Layout.topMargin: 20
            }
            RowLayout {
                Layout.fillWidth: true
                Ink {
                    Layout.fillWidth: true
                    text: appRoot.usage.rateLimitResetCredits ? "可用重置次数  " + appRoot.usage.rateLimitResetCredits.availableCount : "暂无重置数据"
                }
                SamayaButton {
                    text: "查看重置选项 →"
                    onClicked: Qt.openUrlExternally(view.manageUrl)
                }
            }
            SamayaButton {
                text: "返回设置与连接"
                onClicked: appRoot.nav("settings")
            }
        }
    }
}
