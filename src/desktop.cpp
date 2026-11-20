#include "desktop.h"
#include <QApplication>
#include <QBuffer>
#include <QClipboard>
#include <QDesktopServices>
#include <QFileDialog>
#include <QFileInfo>
#include <QDir>
#include <QProcess>
#include <QImageReader>
#include <QMimeData>
#include <QStyleHints>
#include <QSyntaxHighlighter>
#include <QTextBlock>
#include <qt_windows.h>

namespace {
class ReplyLinkHighlighter final : public QSyntaxHighlighter {
public:
    using QSyntaxHighlighter::QSyntaxHighlighter;
    QColor linkColor;

private:
    void highlightBlock(const QString &) override
    {
        const auto block = currentBlock();
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            auto format = fragment.charFormat();
            if (format.anchorHref().isEmpty()) continue;
            format.setForeground(linkColor);
            format.setFontUnderline(true);
            setFormat(fragment.position() - block.position(), fragment.length(), format);
        }
    }
};
}

Desktop::Desktop(QQmlEngine *engine, const QString &file) : engine_(engine),
    settings_(file.isEmpty() ? std::make_unique<QSettings>() : std::make_unique<QSettings>(file, QSettings::IniFormat))
{
    connect(&api_, &Api::changed, this, [this](const QString &method, const QJsonObject &params) { emit event(method, params.toVariantMap()); });
    connect(&api_, &Api::disconnected, this, &Desktop::lost);
    connect(qApp->styleHints(), &QStyleHints::colorSchemeChanged, this, &Desktop::appearanceChanged);
}
Api::Callback Desktop::reply(QJSValue callback)
{
    return [this, callback](const Response &r) mutable {
        if (callback.isCallable()) {
            auto result = callback.call({engine_->toScriptValue(r.data.toVariantMap()), QJSValue(r.error)});
            if (result.isError()) qWarning().noquote() << result.property("stack").toString();
        }
    };
}
void Desktop::connectServer(QJSValue callback) { api_.start(reply(callback)); }
void Desktop::read(const QString &path, const QVariantMap &params, QJSValue callback)
{
    QUrlQuery query;
    for (auto it = params.begin(); it != params.end(); ++it) query.addQueryItem(it.key(), it.value().toString());
    api_.get(path, reply(callback), query);
}
void Desktop::act(const QString &op, const QVariantMap &params, QJSValue cb) { api_.operate(op, QJsonObject::fromVariantMap(params), reply(cb)); }
void Desktop::login(QJSValue cb)
{
    api_.login([done = reply(cb)](Response r) {
        const auto url = QUrl(r.data.value("authUrl").toString());
        if (r.ok() && (url.scheme() != "https" || !QDesktopServices::openUrl(url))) r.error = tr("无法打开登录页。");
        done(r);
    });
}
QString Desktop::directory(const QString &initial) { return QFileDialog::getExistingDirectory(nullptr, tr("选择工作目录"), initial); }
bool Desktop::openWorkspaceFile(const QString &root, const QString &path)
{
    const auto base = QFileInfo(root).canonicalFilePath();
    if (base.isEmpty()) return false;
    const auto child = QFileInfo(QDir(base).absoluteFilePath(path)).canonicalFilePath();
    if (!child.startsWith(base + '/', Qt::CaseInsensitive)) return false;
    return QProcess::startDetached("explorer.exe", {"/select,", QDir::toNativeSeparators(child)});
}
QStringList Desktop::files() { return QFileDialog::getOpenFileNames(nullptr, tr("添加附件")); }
void Desktop::copy(const QString &text) { QApplication::clipboard()->setText(text); }
void Desktop::styleReplyLinks(QQuickTextDocument *view, const QColor &color)
{
    auto *doc = view ? view->textDocument() : nullptr;
    if (!doc) return;
    const QString name = QStringLiteral("samayaReplyLinks");
    auto *links = dynamic_cast<ReplyLinkHighlighter *>(doc->findChild<QSyntaxHighlighter *>(name, Qt::FindDirectChildrenOnly));
    if (!links) {
        links = new ReplyLinkHighlighter(doc);
        links->setObjectName(name);
    }
    if (links->linkColor != color) {
        links->linkColor = color;
        links->rehighlight();
    }
}
namespace {
QVariantMap imageData(const QImage &image, const QString &name)
{
    if (image.isNull()) return {};
    QBuffer buffer;
    buffer.open(QIODevice::WriteOnly);
    if (!image.save(&buffer, "PNG") || buffer.size() > 16 * 1024 * 1024) return {};
    return {{"name", name}, {"url", "data:image/png;base64," + QString::fromLatin1(buffer.data().toBase64())}};
}
}
QVariantMap Desktop::attachment(const QUrl &url)
{
    QFileInfo file(url.isLocalFile() ? url.toLocalFile() : url.toString());
    if (!file.isFile()) return {};
    QImageReader reader(file.absoluteFilePath());
    if (reader.canRead()) return imageData(reader.read(), file.fileName());
    return {{"name", file.fileName()}, {"id", file.absoluteFilePath()}};
}
QVariantMap Desktop::clipboardImage() { return imageData(QApplication::clipboard()->image(), tr("粘贴的图片")); }
void Desktop::saveArtifact(const QString &id, const QString &path, QJSValue cb)
{
    const auto dest = QFileDialog::getSaveFileName(nullptr, tr("保存产物"), QFileInfo(path).fileName());
    if (dest.isEmpty()) return;
    QUrlQuery query;
    query.addQueryItem("path", path);
    api_.download("/threads/" + Api::segment(id), dest, query, reply(cb));
}
QVariant Desktop::setting(const QString &key, const QVariant &fallback) const { return settings_->value(key, fallback); }
void Desktop::save(const QString &key, const QVariant &value) { settings_->setValue(key, value); }
bool Desktop::systemDark() const { return qApp->styleHints()->colorScheme() == Qt::ColorScheme::Dark; }
bool Desktop::reducedMotion() const
{
    BOOL enabled = TRUE;
    return SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0) && !enabled;
}
