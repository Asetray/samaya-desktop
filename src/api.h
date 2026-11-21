#pragma once

#include "control-channel.h"
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QProcess>
#include <QSet>
#include <QTimer>
#include <QUrlQuery>
#include <functional>
#include <memory>

class NativeStdio;

struct Response {
    QJsonObject data;
    QString error;
    int status = 0;
    bool ok() const { return error.isEmpty(); }
};

class Api : public QObject {
    Q_OBJECT

public:
    using Callback = std::function<void(Response)>;

    explicit Api(QObject *parent = nullptr);
    ~Api() override;
    static QString segment(const QString &value);
    bool ready() const { return ready_; }
    void start(Callback done);
    void get(const QString &path, Callback done, const QUrlQuery &query = {});
    void download(const QString &path, const QString &destination, const QUrlQuery &query, Callback done);
    void operate(const QString &action, const QJsonObject &body, Callback done);
    void login(Callback done);

signals:
    void changed(const QString &method, const QJsonObject &params);
    void disconnected();

private:
    void rpc(const QString &method, const QJsonObject &params, Callback done);
    bool writeMessage(const QJsonObject &message);
    void consumeMessages(const QByteArray &bytes);
    void onMessage(const QJsonObject &message);
    void onEvent(const QString &method, QJsonObject params);
    void failConnection(const QString &reason);
    void rememberThread(const QJsonObject &result);
    QJsonObject monitoredThread(const QJsonObject &thread) const;
    QJsonObject withLiveTurn(QJsonObject thread) const;
    QJsonArray requestsFor(const QString &threadId) const;
    void cleanupPreview(const QString &id, Callback done);
    void collectDescendants(QJsonObject params, QJsonArray scope, Callback done);
    void checkCleanupTerminals(const QJsonArray &scope, qsizetype index, Callback done);
    bool pagedHistory_ = true;
    void readTurns(const QString &id, const QString &cursor, Callback done);
    void readThread(const QString &id, bool subscribe, Callback done);
    void resumeThread(const QString &id, Callback done);
    void monitor(Callback done);
    void modelSettings(const QString &id, const QString &cwd, Callback done);
    void modelPage(const QString &cursor, QJsonArray rows, Callback done);
    void updateModel(const QJsonObject &body, Callback done);

    void startProxy();
    void startDaemon();
    void initialize();
    ControlChannel channel_;
    QProcess process_;
    QProcess daemonStarter_;
#ifdef Q_OS_WIN
    std::unique_ptr<NativeStdio> stdio_;
    QTimer stdioTimer_;
#endif
    Callback starting_;
    QHash<qint64, Callback> replies_;
    QHash<QString, QJsonObject> pending_;
    QHash<QString, QJsonObject> threads_;
    QHash<QString, QJsonObject> threadSettings_;
    QHash<QString, QJsonObject> liveTurns_;
    QHash<QString, QJsonObject> lastTurns_;
    QSet<QString> subscribed_;
    QSet<QString> externalWriters_;
    qint64 nextId_ = 0, connectionAttempt_ = 0;
    bool ready_ = false, shuttingDown_ = false, triedDaemonStart_ = false;
};
