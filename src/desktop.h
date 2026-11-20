#pragma once
#include "api.h"
#include <QJSValue>
#include <QQmlEngine>
#include <QQuickTextDocument>
#include <QSettings>

class Desktop final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool reducedMotion READ reducedMotion CONSTANT)
    Q_PROPERTY(bool systemDark READ systemDark NOTIFY appearanceChanged)
public:
    Desktop(QQmlEngine *engine, const QString &settingsFile);
    Q_INVOKABLE void connectServer(QJSValue callback);
    Q_INVOKABLE void read(const QString &path, const QVariantMap &params, QJSValue callback);
    Q_INVOKABLE void act(const QString &action, const QVariantMap &params, QJSValue callback);
    Q_INVOKABLE void login(QJSValue callback);
    Q_INVOKABLE QString directory(const QString &initial);
    Q_INVOKABLE QStringList files();
    Q_INVOKABLE bool openWorkspaceFile(const QString &root, const QString &path);
    Q_INVOKABLE QVariantMap attachment(const QUrl &url);
    Q_INVOKABLE QVariantMap clipboardImage();
    Q_INVOKABLE void copy(const QString &text);
    Q_INVOKABLE void styleReplyLinks(QQuickTextDocument *view, const QColor &color);
    Q_INVOKABLE void saveArtifact(const QString &id, const QString &path, QJSValue callback);
    Q_INVOKABLE QVariant setting(const QString &key, const QVariant &fallback) const;
    Q_INVOKABLE void save(const QString &key, const QVariant &value);
    bool reducedMotion() const;
    bool systemDark() const;
signals:
    void event(const QString &method, const QVariantMap &params);
    void lost();
    void appearanceChanged();
private:
    Api::Callback reply(QJSValue callback);
    QQmlEngine *engine_;
    std::unique_ptr<QSettings> settings_;
    Api api_;
};
