import QtQuick
import "Util.js" as U

ListModel {
    id: rows
    required property var source
    required property var keyFor
    property int limit: -1
    property bool holdOrder: false
    property bool ready: false
    readonly property Component rowComponent: Component {
        QtObject {
            required property string key
            required property var value
        }
    }

    function sync() {
        if (!ready) return
        const data = new Map()
        for (let i = 0; i < source.length; ++i)
            data.set(String(keyFor(source[i], i)), source[i])
        const order = new Set()
        if (holdOrder) {
            for (let i = 0; i < count; ++i) {
                const key = get(i).row.key
                if (data.has(key)) order.add(key)
            }
        }
        for (const key of data.keys()) order.add(key)
        const keys = Array.from(order).slice(0, limit < 0 ? order.size : limit)
        const visibleKeys = new Set(keys)
        for (let i = count - 1; i >= 0; --i) {
            const holder = get(i).row
            if (!visibleKeys.has(holder.key)) {
                remove(i)
                holder.destroy()
            }
        }
        for (let i = 0; i < keys.length; ++i) {
            const key = keys[i], value = data.get(key)
            let j = i
            while (j < count && get(j).row.key !== key) ++j
            if (j === count) {
                insert(i, {row: rowComponent.createObject(rows, {key: key, value: value})})
            } else {
                if (j !== i) move(j, i, 1)
                const holder = get(i).row
                if (!U.sameData(holder.value, value)) holder.value = value
            }
        }
    }
    onSourceChanged: sync()
    onLimitChanged: sync()
    onHoldOrderChanged: if (!holdOrder) sync()
    Component.onCompleted: { ready = true; sync() }
}
