#include "api.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <algorithm>
#include <utility>

namespace {
QString threadIdFrom(const QString &path)
{
    return QUrl::fromPercentEncoding(path.section('/', 2, 2).toUtf8());
}

QString queryValue(const QUrlQuery &query, const QString &key)
{
    return query.queryItemValue(key, QUrl::FullyDecoded);
}

QJsonObject settingsFrom(const QJsonObject &reply)
{
    QJsonObject settings;
    const auto thread = reply.value("thread").toObject();
    for (const auto &key : {"model", "reasoningEffort", "serviceTier"}) {
        if (!thread.value(key).isNull() && thread.contains(key)) settings.insert(key, thread.value(key));
        if (reply.contains(key)) settings.insert(key, reply.value(key));
    }
    return settings;
}

QJsonObject operationResult(const QJsonObject &result)
{
    return {{"state", "succeeded"}, {"result", result}};
}

QJsonArray messageInput(const QJsonObject &body)
{
    QJsonArray input;
    auto text = body.value("text").toString();
    for (const auto &file : body.value("files").toArray()) {
        const auto path = file.toObject().value("id").toString();
        if (!path.isEmpty()) text += "\n" + QObject::tr("附件文件") + "：" + QDir::toNativeSeparators(path);
    }
    if (!text.trimmed().isEmpty()) input.append(QJsonObject{{"type", "text"}, {"text", text}});
    for (const auto &image : body.value("images").toArray()) {
        const auto url = image.toObject().value("url").toString();
        if (!url.isEmpty()) input.append(QJsonObject{{"type", "image"}, {"url", url}});
    }
    for (const auto &value : body.value("references").toArray()) {
        const auto ref = value.toObject();
        if (ref.value("type") == "skill" || ref.value("type") == "mention") input.append(ref);
    }
    return input;
}
}

void Api::rememberThread(const QJsonObject &result)
{
    auto thread = result.value("thread").toObject();
    const auto id = thread.value("id").toString();
    if (id.isEmpty()) return;
    const auto settings = settingsFrom(result);
    for (auto i = settings.begin(); i != settings.end(); ++i) threadSettings_[id].insert(i.key(), i.value());
    const auto turns = thread.take("turns").toArray();
    if (!turns.isEmpty()) {
        const auto latest = turns.last().toObject();
        if (!liveTurns_.contains(id) && lastTurns_.value(id).value("id") != latest.value("id")) {
            auto summary = latest;
            summary.remove("items");
            lastTurns_.insert(id, summary);
        }
    }
    threads_.insert(id, thread);
}

QJsonObject Api::withLiveTurn(QJsonObject thread) const
{
    const auto id = thread.value("id").toString();
    thread.insert("externalWriter", externalWriters_.contains(id));
    const auto settings = threadSettings_.value(id);
    for (auto i = settings.begin(); i != settings.end(); ++i) thread.insert(i.key(), i.value());
    const auto cached = liveTurns_.value(id, lastTurns_.value(id));
    if (!cached.contains("items") || cached.value("id").toString().isEmpty()) return thread;
    auto turns = thread.value("turns").toArray();
    for (qsizetype i = 0; i < turns.size(); ++i) {
        if (turns.at(i).toObject().value("id") != cached.value("id")) continue;
        if (liveTurns_.contains(id) || turns.at(i).toObject().value("status") == "inProgress") {
            auto merged = turns.at(i).toObject();
            auto items = merged.value("items").toArray();
            for (const auto &item : cached.value("items").toArray()) {
                const auto itemId = item.toObject().value("id");
                qsizetype index = 0;
                while (index < items.size() && items.at(index).toObject().value("id") != itemId) ++index;
                if (index == items.size()) items.append(item);
                else items.replace(index, item);
            }
            merged.insert("items", items);
            merged.insert("status", cached.value("status"));
            turns.replace(i, merged);
        }
        thread.insert("turns", turns);
        return thread;
    }
    turns.append(cached);
    thread.insert("turns", turns);
    return thread;
}

QJsonArray Api::requestsFor(const QString &threadId) const
{
    QJsonArray requests;
    for (const auto &request : pending_) {
        if (threadId.isEmpty() || request.value("params").toObject().value("threadId") == threadId) requests.append(request);
    }
    return requests;
}

QJsonObject Api::monitoredThread(const QJsonObject &thread) const
{
    const auto id = thread.value("id").toString();
    auto last = liveTurns_.value(id, lastTurns_.value(id));
    last.remove("items");
    return {{"thread", thread}, {"turn", last}, {"confirmedAt", 1}};
}

void Api::monitor(Callback done)
{
    rpc("thread/list", {{"limit", 100}, {"archived", false}, {"sortKey", "updated_at"}, {"useStateDbOnly", true}},
        [this, done = std::move(done)](Response reply) {
            if (!reply.ok()) { done(reply); return; }
            QJsonArray records;
            QSet<QString> listed;
            for (const auto &value : reply.data.value("data").toArray()) {
                auto thread = value.toObject();
                const auto id = thread.value("id").toString();
                if (id.isEmpty()) continue;
                thread.insert("archived", false);
                thread.remove("turns");
                threads_.insert(id, thread);
                records.append(monitoredThread(thread));
                listed.insert(id);
            }
            for (const auto &id : subscribed_) {
                if (listed.contains(id) || !threads_.contains(id)) continue;
                const auto thread = threads_.value(id);
                if (thread.value("archived").toBool()) continue;
                records.append(monitoredThread(thread));
            }
            done({{{"connection", "connected"}, {"initialized", true}, {"records", records}, {"pendingRequests", requestsFor({})}}, {}});
        });
}

void Api::readThread(const QString &id, bool subscribe, Callback done)
{
    const auto wrap = [this, id, done = std::move(done)](Response reply) {
        if (!reply.ok()) { done(reply); return; }
        auto thread = reply.data.value("thread").toObject();
        if (thread.isEmpty()) { done({{}, tr("Codex 没有返回此会话。")}); return; }
        const auto archived = threads_.value(id).value("archived");
        if (archived.isBool()) thread.insert("archived", archived);
        reply.data.insert("thread", thread);
        rememberThread(reply.data);
        done({{{"thread", withLiveTurn(thread)}, {"pendingRequests", requestsFor(id)}, {"historyCursor",reply.data.value("historyCursor")}}, {}});
    };
    const auto history = [this, id, wrap](Response header) {
        if (!header.ok()) { wrap(header); return; }
        const auto fallback = [this, id, header, wrap] {
            rpc("thread/read", {{"threadId", id}, {"includeTurns", true}}, [header, wrap](Response full) {
                if (full.status == -32601) wrap(header);
                else wrap(full);
            });
        };
        if (!pagedHistory_) { fallback(); return; }
        readTurns(id, {}, [this, header, wrap, fallback](Response page) mutable {
            if (!page.ok()) {
                if (page.status == -32601) pagedHistory_ = false;
                fallback();
                return;
            }
            auto thread = header.data.value("thread").toObject();
            thread.insert("turns", page.data.value("data"));
            header.data.insert("thread", thread);
            header.data.insert("historyCursor", page.data.value("nextCursor"));
            wrap(header);
        });
    };
    const auto read = [this, id, history] {
        rpc("thread/read", {{"threadId", id}, {"includeTurns", false}}, history);
    };
    if (!subscribe || subscribed_.contains(id) || threads_.value(id).value("archived").toBool()) {
        read();
        return;
    }
    resumeThread(id, [read, history](Response reply) {
        if (!reply.ok()) { read(); return; }
        history(reply);
    });
}

void Api::resumeThread(const QString &id, Callback done)
{
    rpc("thread/resume", {{"threadId", id}, {"excludeTurns", true}}, [this, id, done](Response reply) {
        if (reply.ok() && reply.data.value("thread").toObject().value("id") != id)
            reply.error = tr("Codex 未确认已恢复这条会话。");
        if (reply.ok()) {
            subscribed_.insert(id);
            externalWriters_.remove(id);
            rememberThread(reply.data);
        } else if (reply.error.contains("active writer", Qt::CaseInsensitive)) {
            subscribed_.remove(id);
            externalWriters_.insert(id);
            reply.data.insert("externalWriter", true);
            reply.error = tr("另一 Codex 实例正在使用这条会话。");
        }
        done(reply);
    });
}

void Api::readTurns(const QString &id, const QString &cursor, Callback done)
{
    QJsonObject params{{"threadId",id}, {"limit",12}, {"itemsView","full"}, {"sortDirection","desc"}};
    if (!cursor.isEmpty()) params.insert("cursor", cursor);
    rpc("thread/turns/list", params, [done = std::move(done)](Response page) {
        if (page.ok()) {
            const auto newestFirst = page.data.value("data").toArray();
            QJsonArray oldestFirst;
            for (auto i = newestFirst.size(); i > 0; --i) oldestFirst.append(newestFirst.at(i-1));
            page.data.insert("data",oldestFirst);
        }
        done(page);
    });
}

void Api::modelPage(const QString &cursor, QJsonArray rows, Callback done)
{
    QJsonObject params{{"limit", 100}};
    if (!cursor.isEmpty()) params.insert("cursor", cursor);
    rpc("model/list", params, [this, cursor, rows, done](Response reply) mutable {
        if (!reply.ok()) { done(reply); return; }
        for (const auto &model : reply.data.value("data").toArray()) rows.append(model);
        const auto next = reply.data.value("nextCursor").toString();
        if (next.isEmpty()) done({{{"data", rows}}, {}});
        else if (next == cursor) done({{}, tr("Codex 返回了重复的模型目录分页标记。")});
        else modelPage(next, std::move(rows), done);
    });
}

void Api::modelSettings(const QString &id, const QString &cwd, Callback done)
{
    const auto load = [this, id, done](QJsonObject configured) {
        modelPage({}, {}, [this, id, configured, done](Response reply) {
        if (!reply.ok()) { done(reply); return; }
        auto current = id.isEmpty() ? configured : threadSettings_.value(id);
        QJsonArray models;
        for (const auto &value : reply.data.value("data").toArray()) {
            auto model = value.toObject();
            const auto name = model.value("model").toString();
            if (name.isEmpty() || (model.value("hidden").toBool() && current.value("model") != name)) continue;
            QJsonArray options;
            for (const auto &option : model.value("supportedReasoningEfforts").toArray()) {
                const auto effort = option.toObject();
                options.append(QJsonObject{{"value", effort.value("reasoningEffort")}, {"label", effort.value("description")}});
            }
            model.insert("effortOptions", options);
            if (current.value("model").toString().isEmpty() && model.value("isDefault").toBool())
                current.insert("model", name);
            models.append(model);
        }
        if (current.value("model").toString().isEmpty() && !models.isEmpty())
            current.insert("model", models.first().toObject().value("model"));
        for (const auto &value : models) {
            const auto model = value.toObject();
            if (model.value("model") != current.value("model")) continue;
            if (current.value("reasoningEffort").toString().isEmpty()) current.insert("reasoningEffort", model.value("defaultReasoningEffort"));
            if (!current.contains("serviceTier")) current.insert("serviceTier", model.value("defaultServiceTier"));
            break;
        }
        if (current.value("serviceTier").toString().isEmpty()) current.insert("serviceTier", "default");
        const bool editable = !liveTurns_.contains(id) && !threads_.value(id).value("archived").toBool();
        done({{{"models", models}, {"current", current}, {"editable", editable}, {"expectedTurnId", lastTurns_.value(id).value("id")}}, {}});
        });
    };
    if (!id.isEmpty()) { load({}); return; }
    QJsonObject params{{"includeLayers", false}};
    if (!cwd.isEmpty()) params.insert("cwd", cwd);
    rpc("config/read", params, [load, done](Response reply) {
        if (!reply.ok()) { done(reply); return; }
        const auto config = reply.data.value("config").toObject();
        QJsonObject current;
        for (const auto &pair : {std::pair{"model", "model"}, {"model_reasoning_effort", "reasoningEffort"}, {"service_tier", "serviceTier"}})
            if (config.value(pair.first).isString()) current.insert(pair.second, config.value(pair.first));
        load(current);
    });
}

void Api::cleanupPreview(const QString &id, Callback done)
{
    rpc("thread/read", {{"threadId", id}, {"includeTurns", false}}, [this, id, done = std::move(done)](Response reply) {
        if (!reply.ok()) { done(reply); return; }
        const QJsonArray kinds{"cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview",
                               "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"};
        collectDescendants({{"ancestorThreadId", id}, {"archived", false}, {"limit", 100},
                            {"sourceKinds", kinds}, {"useStateDbOnly", true}},
                           QJsonArray{reply.data.value("thread")}, std::move(done));
    });
}

void Api::collectDescendants(QJsonObject params, QJsonArray scope, Callback done)
{
    rpc("thread/list", params, [this, params, scope, done = std::move(done)](Response reply) mutable {
        if (!reply.ok()) { done(reply); return; }
        for (const auto &child : reply.data.value("data").toArray()) scope.append(child);
        const auto cursor = reply.data.value("nextCursor").toString();
        if (!cursor.isEmpty()) params.insert("cursor", cursor);
        else if (!params.value("archived").toBool()) {
            params.insert("archived", true);
            params.remove("cursor");
        } else {
            checkCleanupTerminals(scope, 0, std::move(done));
            return;
        }
        collectDescendants(params, scope, std::move(done));
    });
}

void Api::checkCleanupTerminals(const QJsonArray &scope, qsizetype index, Callback done)
{
    for (; index < scope.size(); ++index) {
        const auto thread = scope.at(index).toObject();
        const auto id = thread.value("id").toString();
        const auto status = thread.value("status").toObject().value("type").toString();
        if (id.isEmpty() || liveTurns_.contains(id) || (status != "idle" && status != "notLoaded" && status != "systemError")) {
            done({{}, tr("会话或子会话仍在运行，或无法确认其状态。")});
            return;
        }
        if (status == "notLoaded") continue;
        rpc("thread/backgroundTerminals/list", {{"threadId", id}, {"limit", 1}},
            [this, scope, index, done = std::move(done)](Response reply) {
                if (!reply.ok()) { done(reply); return; }
                if (!reply.data.value("data").toArray().isEmpty()) {
                    done({{}, tr("会话或子会话仍有后台命令。")});
                    return;
                }
                checkCleanupTerminals(scope, index + 1, done);
            });
        return;
    }
    QStringList fingerprints;
    QJsonArray rows;
    for (const auto &value : scope) {
        const auto thread = value.toObject();
        const QJsonObject row{{"id", thread.value("id")}, {"name", thread.value("name").toString(thread.value("preview").toString())},
                              {"cwd", thread.value("cwd")}, {"status", thread.value("status")}, {"updatedAt", thread.value("updatedAt")}};
        rows.append(row);
        fingerprints.append(QString::fromUtf8(QJsonDocument(row).toJson(QJsonDocument::Compact)));
    }
    fingerprints.sort();
    const auto hash = QCryptographicHash::hash(fingerprints.join('\n').toUtf8(), QCryptographicHash::Sha256);
    done({{{"scope", rows}, {"digest", QString::fromLatin1(hash.toHex())}}, {}});
}

void Api::get(const QString &path, Callback done, const QUrlQuery &query)
{
    if (!ready_) { done({{}, tr("本机 Codex 尚未连接。")}); return; }
    if (path == "/status") {
        auto root = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
        if (!QDir(root).exists()) root = QDir::homePath();
        done({{{"connection", "connected"}, {"roots", QJsonArray{QDir::toNativeSeparators(root)}}}, {}});
    } else if (path == "/account") {
        rpc("account/read", {}, std::move(done));
    } else if (path == "/usage") {
        rpc("account/rateLimits/read", {}, std::move(done));
    } else if (path == "/models") {
        modelSettings({}, queryValue(query, "cwd"), std::move(done));
    } else if (path == "/permissions") {
        rpc("permissionProfile/list", {{"cwd",queryValue(query,"cwd")}}, std::move(done));
    } else if (path == "/files") {
        const auto cwd = queryValue(query, "cwd");
        const auto term = queryValue(query, "search");
        if (cwd.isEmpty() || term.isEmpty()) { done({}); return; }
        rpc("fuzzyFileSearch", {{"roots", QJsonArray{cwd}}, {"query", term}}, std::move(done));
    } else if (path == "/skills") {
        rpc("skills/list", {{"cwds", QJsonArray{queryValue(query, "cwd")}}}, std::move(done));
    } else if (path == "/apps") {
        rpc("app/list", {{"limit", 100}}, std::move(done));
    } else if (path == "/monitor") {
        monitor(std::move(done));
    } else if (path == "/threads") {
        const bool archived = queryValue(query, "archived") == "true";
        QJsonObject params{{"archived", archived}, {"limit", 50}, {"useStateDbOnly", true}, {"sortKey", "updated_at"}};
        for (const auto &key : {"cwd", "cursor"}) {
            const auto value = queryValue(query, key);
            if (!value.isEmpty()) params.insert(key, value);
        }
        const auto search = queryValue(query, "search");
        if (!search.isEmpty()) params.insert("searchTerm", search);
        rpc("thread/list", params, [this, archived, done = std::move(done)](Response reply) {
            if (reply.ok()) {
                QJsonArray rows;
                for (const auto &value : reply.data.value("data").toArray()) {
                    auto thread = value.toObject();
                    thread.insert("archived", archived);
                    threads_.insert(thread.value("id").toString(), thread);
                    rows.append(thread);
                }
                reply.data.insert("data", rows);
            }
            done(reply);
        });
    } else if (path.startsWith("/threads/")) {
        const auto id = threadIdFrom(path);
        if (path.endsWith("/history")) readTurns(id,queryValue(query,"cursor"),std::move(done));
        else if (path.endsWith("/live")) done({{{"turn",liveTurns_.value(id,lastTurns_.value(id))}}, {}});
        else if (path.endsWith("/goal")) rpc("thread/goal/get", {{"threadId",id}}, std::move(done));
        else if (path.endsWith("/model-settings")) modelSettings(id, {}, std::move(done));
        else if (path.endsWith("/cleanup-preview")) cleanupPreview(id, std::move(done));
        else readThread(id, queryValue(query, "subscribe") == "true", std::move(done));
    } else done({{}, tr("此操作在本机 Codex 中不可用。")});
}

void Api::download(const QString &path, const QString &destination, const QUrlQuery &query, Callback done)
{
    const auto id = threadIdFrom(path);
    auto source = queryValue(query, "path");
    if (QDir::isRelativePath(source)) source = QDir(threads_.value(id).value("cwd").toString()).absoluteFilePath(source);
    QFile file(source);
    if (!QFileInfo(file).isFile() || !file.open(QIODevice::ReadOnly)) { done({{}, tr("本机找不到或无法打开此产物。")}); return; }
    QSaveFile output(destination);
    if (!output.open(QIODevice::WriteOnly)) { done({{}, output.errorString()}); return; }
    while (!file.atEnd()) {
        const auto chunk = file.read(256 * 1024);
        if (file.error() != QFile::NoError) { done({{}, file.errorString()}); return; }
        if (output.write(chunk) != chunk.size()) { done({{}, output.errorString()}); return; }
    }
    done(output.commit() ? Response{} : Response{{}, output.errorString()});
}

void Api::updateModel(const QJsonObject &body, Callback done)
{
    const auto id = body.value("threadId").toString();
    const auto value = body.value("args").toObject().value("value").toString();
    const auto command = body.value("command").toString();
    if (command == "rename") {
        rpc("thread/name/set", {{"threadId", id}, {"name", value}}, std::move(done));
        return;
    }
    if (threads_.value(id).value("archived").toBool() || liveTurns_.contains(id) || value.isEmpty()) {
        done({{}, tr("请在未归档的空闲会话中选择模型或速度。")}); return;
    }
    QJsonObject params{{"threadId", id}};
    if (command == "model") {
        params.insert("model", value);
        const auto args = body.value("args").toObject();
        for (const auto &field : {"effort", "serviceTier"})
            if (args.contains(field)) params.insert(field, args.value(field));
    } else if (command == "reasoning") params.insert("effort", value);
    else if (command == "fast") params.insert("serviceTier", value);
    else { done({{}, tr("未知的模型设置。")}); return; }
    const auto confirmed = [this, id, params, done](Response reply) {
        if (reply.ok()) {
            auto &current = threadSettings_[id];
            for (const auto &key : {"model", "serviceTier"}) if (params.contains(key)) current.insert(key, params.value(key));
            if (params.contains("effort")) current.insert("reasoningEffort", params.value("effort"));
            reply.data = {{"modelSettings", QJsonObject{{"current", current}}}};
        }
        done(reply);
    };
    const auto joinAndSet = [this, id, params, confirmed] {
        resumeThread(id, [this, params, confirmed](Response joined) {
            if (!joined.ok()) { confirmed(joined); return; }
            rpc("thread/settings/update", params, confirmed);
        });
    };
    rpc("thread/settings/update", params, [this, id, confirmed, joinAndSet](Response reply) {
        if (!reply.ok() && reply.error.startsWith("thread not found", Qt::CaseInsensitive)) {
            subscribed_.remove(id);
            joinAndSet();
        } else {
            confirmed(reply);
        }
    });
}

void Api::operate(const QString &action, const QJsonObject &body, Callback done)
{
    const auto id = body.value("threadId").toString();
    const QJsonObject target{{"threadId", id}};
    const auto finish = [done = std::move(done)](Response reply) {
        if (reply.ok()) reply.data = operationResult(reply.data);
        done(reply);
    };
    if (action == "create" || action == "forkWithSettings") {
        const bool fork = action == "forkWithSettings";
        const auto directory = QFileInfo(body.value("cwd").toString());
        QJsonObject start{{"threadSource", "user"}};
        if (fork) {
            if (id.isEmpty()) { finish({{}, tr("未选择源会话。")}); return; }
            start.insert("threadId", id);
            start.insert("excludeTurns", true);
        } else {
            if (!directory.isDir()) { finish({{}, tr("请选择存在的本机工作目录。")}); return; }
            start.insert("cwd", QDir::toNativeSeparators(directory.absoluteFilePath()));
        }
        const auto settings = body.value("settings").toObject();
        const auto model = settings.value("model").toString(body.value("model").toString());
        if (!model.isEmpty()) start.insert("model", model);
        if (settings.contains("serviceTier")) start.insert("serviceTier", settings.value("serviceTier"));
        if (!settings.value("effort").toString().isEmpty())
            start.insert("config", QJsonObject{{"model_reasoning_effort", settings.value("effort")}});
        rpc(fork ? "thread/fork" : "thread/start", start,
            [this, body, id, fork, finish](Response reply) {
                if (!reply.ok()) { finish(reply); return; }
                const auto thread = reply.data.value("thread").toObject();
                const auto created = thread.value("id").toString();
                if (created.isEmpty() || (fork && created == id)) { finish({{}, tr("Codex 未确认新会话。")} ); return; }
                rememberThread(reply.data);
                subscribed_.insert(created);
                const auto title = body.value("name").toString();
                if (title.isEmpty()) { finish({{{"threadId", created}}, {}}); return; }
                rpc("thread/name/set", {{"threadId", created}, {"name", title}}, [created, finish](Response renamed) {
                    finish({{{"threadId", created}, {"warning", renamed.ok() ? QString{} : renamed.error}}, {}});
                });
            });
    } else if (action == "send" || action == "steer") {
        for (const auto &file : body.value("files").toArray()) {
            const auto path = file.toObject().value("id").toString();
            if (!QFileInfo(path).isFile()) { finish({{}, tr("找不到附件文件：%1").arg(path)}); return; }
        }
        const auto input = messageInput(body);
        if (input.isEmpty()) { finish({{}, tr("请输入消息或添加附件。")}); return; }
        auto params = target;
        params.insert("input", input);
        if (action == "steer") params.insert("expectedTurnId", body.value("expectedTurnId"));
        if (action == "send") {
            const auto options = body.value("settings").toObject();
            for (auto key : {"model", "effort", "serviceTier", "collaborationMode"}) {
                if (options.contains(key)) params.insert(key, options.value(key));
            }
        }
        const QString method = action == "steer" ? "turn/steer" : "turn/start";
        if (subscribed_.contains(id)) rpc(method, params, finish);
        else {
            resumeThread(id, [this, method, params, finish](Response reply) {
                if (!reply.ok()) { finish(reply); return; }
                rpc(method, params, finish);
            });
        }
    } else if (action == "review") {
        rpc("review/start", {{"threadId",id},{"target",QJsonObject{{"type","uncommittedChanges"}}}}, finish);
    } else if (action == "goal") {
        rpc("thread/goal/set", {{"threadId",id},{"objective",body.value("value")}}, finish);
    } else if (action == "permission") {
        rpc("thread/settings/update", {{"threadId",id},{"permissions",body.value("value")}}, finish);
    } else if (action == "shell") {
        rpc("thread/shellCommand", {{"threadId", id}, {"command", body.value("command")}}, finish);
    } else if (action == "interrupt") {
        rpc("turn/interrupt", {{"threadId", id}, {"turnId", body.value("turnId")}}, finish);
    } else if (action == "command") {
        updateModel(body, finish);
    } else if (action == "workspace") {
        const auto directory = QFileInfo(body.value("cwd").toString());
        if (!directory.isDir()) { finish({{}, tr("请选择存在的本机工作目录。")}); return; }
        rpc("thread/settings/update", {{"threadId", id}, {"cwd", QDir::toNativeSeparators(directory.absoluteFilePath())}}, finish);
    } else if (action == "respond") {
        const auto key = body.value("requestKey").toString();
        const auto request = pending_.value(key);
        if (request.isEmpty() || request.value("params").toObject().value("threadId") != id ||
            !writeMessage({{"id", request.value("id")}, {"result", body.value("response")}})) {
            finish({{}, tr("此请求已失效，请刷新会话。")} );
            return;
        }
        pending_.remove(key);
        emit changed("request/changed", target);
        finish({});
    } else if (action == "unarchive") {
        rpc("thread/unarchive", target, finish);
    } else if (action == "archive" || action == "delete") {
        cleanupPreview(id, [this, body, target, action, finish](Response reply) {
            if (!reply.ok()) { finish(reply); return; }
            if (reply.data.value("digest") != body.value("digest")) {
                finish({{}, tr("会话已发生变化。请刷新并重新确认。")});
                return;
            }
            const auto scope = reply.data.value("scope").toArray();
            rpc("thread/" + action, target, [this, scope, action, finish](Response result) {
                if (result.ok()) {
                    for (const auto &entry : scope) {
                        const auto removed = entry.toObject().value("id").toString();
                        subscribed_.remove(removed);
                        if (action == "archive" && threads_.contains(removed)) threads_[removed].insert("archived", true);
                        else threads_.remove(removed);
                    }
                }
                finish(result);
            });
        });
    } else finish({{}, tr("未知的会话操作。")});
}
