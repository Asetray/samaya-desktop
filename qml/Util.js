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
    if(i.type==="userMessage") return i.content
        ? Array.from(i.content).filter(c=>c.type==="text" && typeof c.text === "string").map(c=>c.text).join("\n")
        : i.text || ""
    if(i.type==="agentMessage" || i.type==="plan") return i.text||""
    return i.aggregatedOutput || i.output || i.command || i.text || JSON.stringify(i,null,2)
}
function turnEntries(thread, turn, index) {
    const prefix = [thread.id, turn.id || index]
    const key = (kind, id) => JSON.stringify(prefix.concat(kind, id))
    const entries = []
    let answerParts = []
    let lastAnswer
    function finishAnswer() {
        if (lastAnswer)
            lastAnswer.copyText = answerParts.join("\n\n")
        answerParts = []
        lastAnswer = undefined
    }
    for (const [i, item] of (turn.items || []).entries()) {
        const kind = item.type
        if (kind === "reasoning" || kind === "contextCompaction")
            continue
        const entry = {key: key(kind, item.id || i), kind, item}
        if (kind === "userMessage" || item.source === "userShell") {
            finishAnswer()
        } else if (kind === "agentMessage" && item.phase !== "commentary" && (item.text || "").trim()) {
            answerParts.push(item.text)
            lastAnswer = entry
        }
        entries.push(entry)
    }
    finishAnswer()
    return {entries, key}
}
function timeline(thread) {
    const out = []
    const turns = thread.turns || []
    for (let t = 0; t < turns.length; ++t) {
        const turn = turns[t]
        const {entries, key} = turnEntries(thread, turn, t)
        let tools = []
        let toolKey = ""
        function flushTools() {
            if (tools.length) {
                out.push({key: toolKey, kind: "tools", items: tools, turn: turn.status})
                tools = []
            }
        }
        for (const entry of entries) {
            if (entry.kind !== "userMessage" && entry.kind !== "agentMessage" && entry.kind !== "plan") {
                if (!tools.length) toolKey = entry.key
                tools.push(entry.item)
                continue
            }
            flushTools()
            out.push(entry)
        }
        flushTools()
        if (turn.error && turn.error.message)
            out.push({key: key("error", 0), kind: "error", item: {text: turn.error.message}})
    }
    return out
}
function validTime(value) {
    return typeof value === "number" && Number.isFinite(value) && value > 0 && value <= 8640000000000000
}
function itemTime(item, completedFirst) {
    const timing = item.samayaTiming || {}
    const start = timing.startedAtMs
    const end = timing.completedAtMs
    return (completedFirst ? [end, start] : [start, end]).find(validTime)
}
function localDay(at) {
    const d = new Date(at)
    return Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())
}
function conversationTime(at, now) {
    const clock = Qt.formatTime(new Date(at), "hh:mm")
    const today = localDay(now === undefined ? Date.now() : now)
    const day = localDay(at)
    if (day === today)
        return "今天 " + clock
    if (day === today - 86400000)
        return "昨天 " + clock
    const d = new Date(at)
    const year = d.getFullYear() === new Date(now === undefined ? Date.now() : now).getFullYear() ? "" : d.getFullYear() + "年"
    return year + (d.getMonth() + 1) + "月" + d.getDate() + "日 " + clock
}
function activityGroup(item) {
    const app = item.appContext && item.appContext.appName
    const service = item.server || item.namespace
    if (app || item.type === "mcpToolCall") {
        const name = app || service || "外部工具"
        return {key: "app:" + name, label: "使用 " + name}
    }
    if (item.type === "commandExecution")
        return {key: "command", label: "执行命令"}
    if (item.type === "webSearch")
        return {key: "search", label: "搜索网页"}
    if (item.type === "fileChange")
        return {key: "files", label: "修改文件"}
    if (/collab|subAgent/i.test(item.type))
        return {key: "agents", label: "子智能体活动"}
    return {key: item.type + ":" + (item.tool || ""), label: item.tool ? "调用 " + item.tool : "工具活动"}
}
function itemFailed(item) {
    return item.status === "failed" || item.status === "interrupted" || item.success === false
        || (typeof item.exitCode === "number" && item.exitCode !== 0) || !!item.error
}
function processRows(entries) {
    const rows = []
    for (const entry of entries) {
        if (entry.kind === "agentMessage") {
            rows.push(entry)
            continue
        }
        const activity = activityGroup(entry.item)
        let last = rows[rows.length - 1]
        if (!last || last.group !== activity.key) {
            last = {key: entry.key, group: activity.key, label: activity.label, items: [], failures: 0}
            rows.push(last)
        }
        last.items.push(entry)
        if (itemFailed(entry.item))
            ++last.failures
    }
    return rows
}
function conversationTimeline(thread) {
    const out = []
    const turns = thread.turns || []
    let previousTime
    function add(entry, startsExchange) {
        const prior = out[out.length - 1]
        entry.startsExchange = startsExchange
        entry.extraTop = !prior ? 0 : startsExchange ? 16 : prior.kind === "time" ? 8 : prior.kind === "userMessage" ? 4 : 0
        out.push(entry)
    }
    for (const [index, turn] of turns.entries()) {
        const {entries, key} = turnEntries(thread, turn, index)
        const startedAt = validTime(turn.startedAt) && validTime(turn.startedAt * 1000) ? turn.startedAt * 1000 : undefined
        const completedAt = validTime(turn.completedAt) && validTime(turn.completedAt * 1000) ? turn.completedAt * 1000 : undefined
        if (turn.error && turn.error.message)
            add({key: key("error", 0), kind: "error", item: {text: turn.error.message}}, true)
        let firstUser = true
        let exchange = {user: null, process: [], answers: []}
        function finishExchange(last) {
            let startsExchange = true
            function push(entry) {
                add(entry, startsExchange)
                startsExchange = false
            }
            const user = exchange.user
            if (user) {
                const at = itemTime(user.item, false) ?? (firstUser ? startedAt : undefined)
                firstUser = false
                if (at !== undefined && (previousTime === undefined || (at >= previousTime
                    && (at - previousTime >= 3600000 || localDay(at) !== localDay(previousTime))))) {
                    push({key: key("time", user.key), kind: "time", at})
                }
                if (at !== undefined)
                    previousTime = Math.max(previousTime ?? 0, at)
                push(user)
            }
            for (const entry of exchange.process.concat(exchange.answers)) {
                const at = itemTime(entry.item, true)
                if (at !== undefined)
                    previousTime = Math.max(previousTime ?? 0, at)
            }
            const activeExchange = last && index === turns.length - 1 && turn.status === "inProgress"
            if (exchange.process.length || activeExchange || (last && startedAt !== undefined && completedAt >= startedAt)) {
                const tools = exchange.process.filter(entry => entry.kind !== "agentMessage")
                push({key: key("process", user ? user.key : 0), kind: "process", rows: processRows(exchange.process),
                    toolCount: tools.length, failures: tools.filter(entry => itemFailed(entry.item)).length,
                    status: turn.status, active: activeExchange, startedAt, completedAt,
                    hasFinal: exchange.answers.some(entry => entry.item.phase === "final_answer")})
            }
            for (const entry of exchange.answers)
                push(entry)
        }
        for (const entry of entries) {
            if (entry.kind === "userMessage" || entry.item.source === "userShell") {
                if (exchange.user || exchange.process.length || exchange.answers.length)
                    finishExchange(false)
                exchange = {user: entry.item.source === "userShell" ? Object.assign({}, entry, {kind: "userShell"}) : entry,
                    process: [], answers: []}
            } else if (entry.kind === "plan" || (entry.kind === "agentMessage" && entry.item.phase !== "commentary")) {
                if (messageText(entry.item).trim())
                    exchange.answers.push(entry)
            } else {
                exchange.process.push(entry)
            }
        }
        finishExchange(true)
        if (completedAt !== undefined)
            previousTime = Math.max(previousTime ?? 0, completedAt)
    }
    return out
}
function durationLabel(ms) {
    const seconds = Math.max(0, Math.floor(ms / 1000))
    if (seconds < 60)
        return seconds + "秒"
    if (seconds < 3600)
        return Math.floor(seconds / 60) + "分" + seconds % 60 + "秒"
    return Math.floor(seconds / 3600) + "小时" + Math.floor(seconds % 3600 / 60) + "分"
}
function effortLabel(value) {
    return ({none: "关闭", minimal: "极轻", low: "轻度", medium: "标准",
             high: "深入", xhigh: "增强", max: "极深", ultra: "极致"})[value] || value || "";
}
