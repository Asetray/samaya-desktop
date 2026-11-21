#pragma once
#include "api.h"
#include <QJSValue>
#include <QQmlEngine>
#include <QQuickTextDocument>
#include <QSettings>
#include <QWindow>

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
    Q_INVOKABLE bool openReplyLink(const QString &link, const QString &workspace);
    Q_INVOKABLE void styleReply(QQuickTextDocument *view, const QColor &color, const QColor &hoverColor,
                                const QColor &hoverBackground);
    Q_INVOKABLE void setReplyLinkHover(QQuickTextDocument *view, int position);
    Q_INVOKABLE void repaintReplySelection(QQuickTextDocument *view);
    Q_INVOKABLE void styleUserMessage(QQuickTextDocument *view);
    Q_INVOKABLE void styleWindowFrame(QWindow *window, bool dark, const QColor &caption,
                                      const QColor &text, const QColor &border);
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
