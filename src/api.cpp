#include "api.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QTimer>
#include <utility>

#ifdef Q_OS_WIN
#include "native-stdio.h"
#endif

namespace {
QString requestKey(const QJsonValue &id)
{
    return QString::fromUtf8(QJsonDocument(QJsonArray{id}).toJson(QJsonDocument::Compact));
}

bool supportedRequest(const QString &method)
{
    return method == "item/commandExecution/requestApproval" || method == "item/fileChange/requestApproval" ||
           method == "item/permissions/requestApproval" || method == "item/tool/requestUserInput";
}
}

Api::Api(QObject *parent) : QObject(parent)
{
#ifdef Q_OS_WIN
    stdio_ = std::make_unique<NativeStdio>();
    process_.setProcessChannelMode(QProcess::ForwardedChannels);
    process_.setInputChannelMode(QProcess::ForwardedInputChannel);
    process_.setCreateProcessArgumentsModifier([this](QProcess::CreateProcessArguments *args) {
        stdio_->installHandles(args);
    });
    stdioTimer_.setInterval(15);
    connect(&stdioTimer_, &QTimer::timeout, this, [this] {
        QByteArray bytes;
        if (stdio_->pump(bytes)) consumeMessages(bytes);
        else {
            failConnection(tr("Codex 标准输入输出连接已断开。"));
            process_.kill();
        }
    });
#else
    connect(&process_, &QProcess::readyReadStandardOutput, this, [this] { consumeMessages(process_.readAllStandardOutput()); });
    connect(&process_, &QProcess::readyReadStandardError, this, [this] { process_.readAllStandardError(); });
#endif
    connect(&process_, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) failConnection(tr("无法启动本机 Codex：%1").arg(process_.errorString()));
    });
    connect(&process_, &QProcess::finished, this, [this](int code) {
        failConnection(tr("Codex 本地代理已退出（%1）。").arg(code));
    });
    connect(&process_, &QProcess::started, this, [this] {
#ifdef Q_OS_WIN
        stdio_->closeChildHandles();
        stdioTimer_.start();
#endif
        stdio_->send(channel_.handshake());
    });
}

void Api::initialize()
{
    const QJsonObject client{{"name", "samaya_desktop"}, {"title", "Samaya Desktop"}, {"version", SAMAYA_VERSION}};
    rpc("initialize", {{"clientInfo", client}, {"capabilities", QJsonObject{{"experimentalApi", true}}}},
        [this](Response reply) {
            if (!starting_) return;
            if (reply.ok() && !writeMessage({{"method", "initialized"}})) reply.error = tr("Codex 连接已断开。");
            ready_ = reply.ok();
            auto done = std::exchange(starting_, {});
            done(std::move(reply));
            if (!ready_ && process_.state() != QProcess::NotRunning) process_.kill();
        });
}

Api::~Api()
{
    shuttingDown_ = true;
#ifdef Q_OS_WIN
    stdioTimer_.stop();
    stdio_->closeInput();
#endif
    if (process_.state() == QProcess::NotRunning) return;
    process_.closeWriteChannel();
    if (!process_.waitForFinished(1500)) {
        process_.kill();
        process_.waitForFinished(1000);
    }
}

QString Api::segment(const QString &value)
{
    return QString::fromLatin1(QUrl::toPercentEncoding(value));
}

void Api::start(Callback done)
{
    if (ready_) { done({}); return; }
    if (process_.state() != QProcess::NotRunning) { done({{}, tr("Codex 正在启动。")}); return; }
    const auto home = qEnvironmentVariable("CODEX_HOME", QDir::home().filePath(".codex"));
    const auto socket = QDir(home).filePath("app-server-control/app-server-control.sock");
    auto path = QDir(home).filePath("packages/app-server-daemon/current/bin/codex.exe");
    if (!QFileInfo(path).isFile()) path = QStandardPaths::findExecutable("codex.exe");
    if (!QFileInfo(path).isFile()) { done({{}, tr("未找到本机 Codex 代理，请打开已安装的 Codex。")}); return; }
#ifdef Q_OS_WIN
    if (!stdio_->open()) { stdio_->close(); done({{}, tr("无法创建 Codex 本地通信管道。")}); return; }
#endif
    process_.setWorkingDirectory(QDir::homePath());
    process_.setProgram(path);
    process_.setArguments({"app-server", "proxy", "--sock", QDir::toNativeSeparators(socket)});
    starting_ = std::move(done);
    process_.start();
    const auto attempt = ++connectionAttempt_;
    QTimer::singleShot(8000, this, [this, attempt] {
        if (starting_ && connectionAttempt_ == attempt) { failConnection(tr("连接超时，请确认本机 Codex App Server 已运行。")); process_.kill(); }
    });
}

void Api::rpc(const QString &method, const QJsonObject &params, Callback done)
{
    if (!ready_ && method != "initialize") { done({{}, tr("本机 Codex 尚未连接。")}); return; }
    const auto id = ++nextId_;
    if (!writeMessage({{"method", method}, {"id", id}, {"params", params}})) {
        done({{}, tr("无法向本机 Codex 发送请求。")});
        return;
    }
    replies_.insert(id, std::move(done));
    QTimer::singleShot(60000, this, [this, id] {
        auto callback = replies_.take(id);
        if (callback) callback({{}, tr("Codex 响应超时。请先核对会话状态。")});
    });
}

bool Api::writeMessage(const QJsonObject &message)
{
    if (process_.state() != QProcess::Running) return false;
    const auto bytes = ControlChannel::frame(QJsonDocument(message).toJson(QJsonDocument::Compact));
#ifdef Q_OS_WIN
    return stdio_->send(bytes);
#else
    return process_.write(bytes) == bytes.size();
#endif
}

void Api::consumeMessages(const QByteArray &bytes)
{
    if (shuttingDown_ || bytes.isEmpty()) return;
    const bool connected = channel_.upgraded();
    QList<QByteArray> messages, controls;
    if (!channel_.receive(bytes, messages, controls)) {
        failConnection(tr("本机 App Server 的连接已关闭或协议不匹配。"));
        process_.kill();
        return;
    }
    for (const auto &reply : controls) stdio_->send(reply);
    if (!connected && channel_.upgraded()) initialize();
    for (const auto &message : messages) {
        const auto doc = QJsonDocument::fromJson(message);
        if (doc.isObject()) onMessage(doc.object());
    }
}

void Api::onMessage(const QJsonObject &message)
{
    const auto method = message.value("method").toString();
    const auto id = message.value("id");
    if (method.isEmpty()) {
        auto callback = replies_.take(id.toInteger(-1));
        if (!callback) return;
        const auto error = message.value("error").toObject();
        if (!error.isEmpty()) {
            const auto text = error.value("message").toString(tr("Codex 请求失败。"));
            callback(Response{{}, text, error.value("code").toInt()});
        } else callback(Response{message.value("result").toObject(), {}, 0});
        return;
    }
    const auto params = message.value("params").toObject();
    if (id.isUndefined()) {
        onEvent(method, params);
        return;
    }
    if (!supportedRequest(method)) {
        writeMessage({{"id", id}, {"error", QJsonObject{{"code", -32601}, {"message", "Samaya does not support this request"}}}});
        return;
    }
    const auto key = requestKey(id);
    pending_.insert(key, {{"key", key}, {"id", id}, {"method", method}, {"params", params}});
    emit changed("request/changed", params);
}

void Api::failConnection(const QString &reason)
{
#ifdef Q_OS_WIN
    stdioTimer_.stop();
    stdio_->close();
#endif
    const bool wasReady = std::exchange(ready_, false);
    auto starting = std::exchange(starting_, {});
    auto replies = std::exchange(replies_, {});
    pagedHistory_ = true;
    pending_.clear();
    threads_.clear();
    threadSettings_.clear();
    liveTurns_.clear();
    lastTurns_.clear();
    subscribed_.clear();
    externalWriters_.clear();
    if (shuttingDown_) return;
    if (starting) starting({{}, reason});
    for (auto &reply : replies) reply({{}, reason});
    if (wasReady) emit disconnected();
}

void Api::onEvent(const QString &method, QJsonObject params)
{
    auto id = params.value("threadId").toString();
    if (method == "thread/started") {
        const auto thread = params.value("thread").toObject();
        id = thread.value("id").toString();
        if (!id.isEmpty()) threads_.insert(id, thread);
        params.insert("threadId", id);
    } else if (method == "thread/closed" && !id.isEmpty()) {
        subscribed_.remove(id);
        liveTurns_.remove(id);
    } else if (method == "thread/status/changed" && !id.isEmpty()) {
        if (params.value("status").toObject().value("type") == "notLoaded") {
            subscribed_.remove(id);
            liveTurns_.remove(id);
        }
        if (threads_.contains(id)) threads_[id].insert("status", params.value("status"));
    } else if (method == "thread/settings/updated" && !id.isEmpty()) {
        const auto settings = params.value("threadSettings").toObject();
        auto &current = threadSettings_[id];
        for (const auto &key : {"model", "serviceTier"}) if (settings.contains(key)) current.insert(key, settings.value(key));
        if (settings.contains("effort")) current.insert("reasoningEffort", settings.value("effort"));
    } else if (method == "serverRequest/resolved") {
        pending_.remove(requestKey(params.value("requestId")));
        emit changed("request/changed", params);
    } else if (method == "turn/started" && !id.isEmpty()) {
        const auto turn = params.value("turn").toObject();
        liveTurns_.insert(id, turn);
        lastTurns_.insert(id, turn);
    } else if (method == "turn/completed" && !id.isEmpty()) {
        auto turn = params.value("turn").toObject();
        if (turn.value("items").toArray().isEmpty() && turn.value("id") == liveTurns_.value(id).value("id")) {
            turn.insert("items", liveTurns_.value(id).value("items"));
        }
        lastTurns_.insert(id, turn);
        liveTurns_.remove(id);
        for (auto i = pending_.begin(); i != pending_.end();) {
            if (i.value().value("params").toObject().value("turnId") == turn.value("id")) i = pending_.erase(i);
            else ++i;
        }
    } else if ((method == "item/started" || method == "item/completed" || method == "item/agentMessage/delta") && !id.isEmpty()) {
        const auto turnId = params.value("turnId").toString();
        auto turn = liveTurns_.value(id);
        if (turn.value("id").toString() != turnId) turn = {{"id", turnId}, {"status", "inProgress"}, {"items", QJsonArray{}}};
        const bool delta = method == "item/agentMessage/delta";
        auto item = params.value("item").toObject();
        const auto itemId = delta ? params.value("itemId") : item.value("id");
        auto items = turn.value("items").toArray();
        qsizetype index = 0;
        while (index < items.size() && items.at(index).toObject().value("id") != itemId) ++index;
        if (delta) {
            item = index < items.size() ? items.at(index).toObject() : QJsonObject{{"id", itemId}, {"type", "agentMessage"}};
            item.insert("text", item.value("text").toString() + params.value("delta").toString());
        }
        if (index == items.size()) items.append(item);
        else items.replace(index, item);
        turn.insert("items", items);
        liveTurns_.insert(id, turn);
    }
    emit changed(method, params);
}

void Api::login(Callback done)
{
    rpc("account/login/start", {{"type", "chatgpt"}}, std::move(done));
}
