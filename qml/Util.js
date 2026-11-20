.pragma library
function title(t) { return t && (t.name || (t.preview || "").split("\n")[0]) || "未命名对话" }
function base(path) { return (path || "").replace(/[/\\]+$/,"").split(/[/\\]/).pop() || path || "工作区" }
function active(t) { return t && t.status && t.status.type === "active" }
function status(t, turn) {
    if (active(t)) return "运行中"
    const values = {completed:"本轮已结束",interrupted:"本轮已中断",failed:"本轮失败",inProgress:"执行中"}
    return values[(turn||{}).status] || ((t.status||{}).type === "systemError" ? "状态待确认" : "空闲")
}
function grouped(records) {
    let groups = [], by = Object.create(null)
    for (let r of records) {
        let p = r.thread.cwd || ""
        if (!by[p]) { by[p] = {path:p, rows:[]}; groups.push(by[p]) }
        by[p].rows.push(r)
    }
    return groups
}
function date(s) { return s ? Qt.formatDateTime(new Date(Number(s)*1000),"MM/dd hh:mm") : "" }
function speedLabel(id, name) {
    if (!id || id === "default") return "标准";
    if (id === "fast" || id === "priority") return "快速";
    if (id === "ultrafast") return "超快";
    return name || id;
}
function sameData(a, b) {
    if (a === b) return true
    if (!a || !b || typeof a !== "object" || typeof b !== "object") return false
    if (Array.isArray(a) !== Array.isArray(b)) return false
    const keys = Object.keys(a)
    return keys.length === Object.keys(b).length && keys.every(key =>
        Object.prototype.hasOwnProperty.call(b, key) && sameData(a[key], b[key]))
}
function messageText(i) {
    if(i.type==="userMessage") return (i.content||[]).filter(c=>c.type==="text").map(c=>c.text).join("\n")
    if(i.type==="agentMessage" || i.type==="plan") return i.text||""
    return i.aggregatedOutput || i.output || i.command || i.text || JSON.stringify(i,null,2)
}
function timeline(thread) {
    const out = []
    const turns = thread.turns || []
    for (let t = 0; t < turns.length; ++t) {
        const turn = turns[t]
        function rowKey(kind, item, index) {
            return JSON.stringify([thread.id, turn.id || t, kind, item.id || index])
        }
        let tools = []
        let toolKey = ""
        let answerParts = []
        let lastAnswer = null
        function flushTools() {
            if (tools.length) {
                out.push({key: toolKey, kind: "tools", items: tools, turn: turn.status})
                tools = []
            }
        }
        function finishAnswer() {
            if (lastAnswer)
                lastAnswer.copyText = answerParts.join("\n\n")
            answerParts = []
            lastAnswer = null
        }
        const items = turn.items || []
        for (let i = 0; i < items.length; ++i) {
            const item = items[i]
            if (item.type !== "userMessage" && item.type !== "agentMessage" && item.type !== "plan") {
                if (!tools.length) toolKey = rowKey("tools", item, i)
                tools.push(item)
                continue
            }
            flushTools()
            const entry = {key: rowKey(item.type, item, i), kind: item.type, item: item}
            if (item.type === "userMessage") {
                finishAnswer()
            } else if (item.type === "agentMessage" && item.phase !== "commentary" && (item.text || "").trim()) {
                answerParts.push(item.text)
                lastAnswer = entry
            }
            out.push(entry)
        }
        flushTools()
        finishAnswer()
        if (turn.error && turn.error.message)
            out.push({key: rowKey("error", {}, 0), kind: "error", item: {text: turn.error.message}})
    }
    return out
}
function effortLabel(value) {
    return ({none: "关闭", minimal: "极轻", low: "轻度", medium: "标准",
             high: "深入", xhigh: "增强", max: "极深", ultra: "极致"})[value] || value || "";
}
