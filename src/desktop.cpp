#include "desktop.h"
#include <QAbstractTextDocumentLayout>
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
#include <QPainter>
#include <QRegularExpression>
#include <QStyleHints>
#include <QSyntaxHighlighter>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextFrame>
#include <QUrl>
#include <utility>
#include <qt_windows.h>
#include <dwmapi.h>
#include <shlobj.h>

namespace {
const auto replyLinksName = QStringLiteral("samayaReplyLinks");

class ReplyLinkHighlighter final : public QSyntaxHighlighter {
public:
    using QSyntaxHighlighter::QSyntaxHighlighter;
    QColor linkColor;
    QColor hoverColor;
    QColor hoverBackground;

    bool setHoveredPosition(int position)
    {
        const auto block = position >= 0 ? document()->findBlock(position) : QTextBlock{};
        const auto range = linkRange(block, position);
        if (range == hoveredRange_) return false;

        const auto previous = hoveredRange_.first >= 0 ? document()->findBlock(hoveredRange_.first) : QTextBlock{};
        hoveredRange_ = range;
        if (previous.isValid()) rehighlightBlock(previous);
        if (range.first >= 0 && block != previous) rehighlightBlock(block);
        return true;
    }

private:
    static std::pair<int, int> linkRange(const QTextBlock &block, int position)
    {
        if (!block.isValid()) return {-1, -1};
        QString href;
        int start = -1, end = -1;
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            const auto anchor = fragment.charFormat().anchorHref();
            if (anchor != href) {
                if (fragment.position() > position) break;
                href = anchor;
                start = fragment.position();
            }
            end = fragment.position() + fragment.length();
        }
        if (!href.isEmpty() && position >= start && position < end) return {start, end};
        return {-1, -1};
    }

    void highlightBlock(const QString &) override
    {
        const auto block = currentBlock();
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            auto format = fragment.charFormat();
            if (format.anchorHref().isEmpty()) continue;
            const auto position = fragment.position();
            const bool hovered = position >= hoveredRange_.first && position < hoveredRange_.second;
            format.setForeground(hovered ? hoverColor : linkColor);
            if (hovered) format.setBackground(hoverBackground);
            format.setFontUnderline(true);
            setFormat(fragment.position() - block.position(), fragment.length(), format);
        }
    }

    std::pair<int, int> hoveredRange_{-1, -1};
};

ReplyLinkHighlighter *replyLinks(QTextDocument *doc)
{
    return dynamic_cast<ReplyLinkHighlighter *>(doc->findChild<QSyntaxHighlighter *>(replyLinksName, Qt::FindDirectChildrenOnly));
}

bool isDrivePath(QStringView path)
{
    if (path.size() < 3 || path[1] != u':' || path[2] != u'/') return false;
    const auto letter = path[0].toUpper();
    return letter >= u'A' && letter <= u'Z';
}

bool isLocalDrivePath(const QString &path)
{
    if (!isDrivePath(path)) return false;
    const auto drive = QDir::toNativeSeparators(path.left(3));
    const auto type = GetDriveTypeW(reinterpret_cast<LPCWSTR>(drive.utf16()));
    return type != DRIVE_UNKNOWN && type != DRIVE_NO_ROOT_DIR && type != DRIVE_REMOTE;
}

bool selectFileInExplorer(const QString &path)
{
    if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) return false;
    const auto nativePath = QDir::toNativeSeparators(path);
    PIDLIST_ABSOLUTE item = nullptr;
    const auto parsed = SHParseDisplayName(reinterpret_cast<LPCWSTR>(nativePath.utf16()), nullptr, &item, 0, nullptr);
    const bool selected = SUCCEEDED(parsed) && item && SUCCEEDED(SHOpenFolderAndSelectItems(item, 0, nullptr, 0));
    CoTaskMemFree(item);
    CoUninitialize();
    return selected;
}
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
bool Desktop::openReplyLink(const QString &link, const QString &workspace)
{
    const QUrl url(link, QUrl::StrictMode);
    if (url.scheme() == "http" || url.scheme() == "https")
        return url.isValid() && !url.host().isEmpty() && QDesktopServices::openUrl(url);

    if (url.isLocalFile() && (!url.isValid() || !url.host().isEmpty())) return false;
    auto path = QDir::fromNativeSeparators(url.isLocalFile() ? url.toLocalFile() : QUrl::fromPercentEncoding(link.toUtf8()));
    if (path.startsWith(u'/') && isDrivePath(QStringView(path).sliced(1))) path.remove(0, 1);
    static const QRegularExpression sourceLocation(QStringLiteral(":[0-9]+(?::[0-9]+)?\\z"));
    const auto location = sourceLocation.match(path);
    if (location.hasMatch()) path.truncate(location.capturedStart());
    if (path.isEmpty() || path.contains(u'\0')) return false;

    if (!isDrivePath(path)) {
        // Markdown can interpret an unprefixed filename followed by a line number as a URL scheme.
        const bool sourceFile = location.hasMatch() && path.contains(u'.');
        if (path.startsWith(u'/') || path.contains(u':') || (!url.isRelative() && !sourceFile)) return false;
        const auto base = QDir::fromNativeSeparators(workspace);
        if (!isLocalDrivePath(base)) return false;
        path = QDir(base).absoluteFilePath(path);
    }
    if (!isLocalDrivePath(path) || path.indexOf(u':', 3) >= 0) return false;

    const QFileInfo file(path);
    const auto target = file.canonicalFilePath();
    if (!isLocalDrivePath(target)) return false;
    if (file.isDir()) return QDesktopServices::openUrl(QUrl::fromLocalFile(target));
    return file.isFile() && selectFileInExplorer(target);
}

void Desktop::styleReply(QQuickTextDocument *view, const QColor &color, const QColor &hoverColor,
                         const QColor &hoverBackground)
{
    auto *doc = view ? view->textDocument() : nullptr;
    if (!doc) return;
    QTextCursor cursor(doc);
    cursor.beginEditBlock();
    for (auto block = doc->begin(); block.isValid(); block = block.next()) {
        auto format = block.blockFormat();
        if (format.headingLevel() || format.nonBreakableLines() || format.hasProperty(QTextFormat::BlockCodeFence))
            continue;
        constexpr qreal lineHeight = 30.4;
        if (format.lineHeightType() == QTextBlockFormat::FixedHeight && qFuzzyCompare(format.lineHeight(), lineHeight))
            continue;
        format.setLineHeight(lineHeight, QTextBlockFormat::FixedHeight);
        cursor.setPosition(block.position());
        cursor.setBlockFormat(format);
    }
    cursor.endEditBlock();
    auto *links = replyLinks(doc);
    if (!links) {
        links = new ReplyLinkHighlighter(doc);
        links->setObjectName(replyLinksName);
    }
    if (links->linkColor != color || links->hoverColor != hoverColor || links->hoverBackground != hoverBackground) {
        links->linkColor = color;
        links->hoverColor = hoverColor;
        links->hoverBackground = hoverBackground;
        links->rehighlight();
    }
}

void Desktop::setReplyLinkHover(QQuickTextDocument *view, int position)
{
    auto *doc = view ? view->textDocument() : nullptr;
    auto *links = doc ? replyLinks(doc) : nullptr;
    if (links && links->setHoveredPosition(position))
        repaintReplySelection(view);
}
void Desktop::repaintReplySelection(QQuickTextDocument *view)
{
    auto *doc = view ? view->textDocument() : nullptr;
    if (!doc || doc->rootFrame()->childFrames().isEmpty()) return;

    // Qt Quick can append nested table glyphs to retained nodes on a partial selection update.
    auto *layout = doc->documentLayout();
    for (auto block = doc->begin(); block.isValid(); block = block.next())
        emit layout->updateBlock(block);
}

void Desktop::styleUserMessage(QQuickTextDocument *view)
{
    auto *doc = view ? view->textDocument() : nullptr;
    if (!doc) return;
    QTextBlockFormat format;
    format.setLineHeight(28, QTextBlockFormat::FixedHeight);
    QTextCursor cursor(doc);
    cursor.select(QTextCursor::Document);
    cursor.mergeBlockFormat(format);
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
void Desktop::styleWindowFrame(QWindow *window, bool dark, const QColor &caption,
                              const QColor &text, const QColor &border)
{
    if (!window || QGuiApplication::platformName() != "windows") return;
    const auto handle = reinterpret_cast<HWND>(window->winId());
    const BOOL darkFrame = dark ? TRUE : FALSE;
    constexpr DWORD legacyImmersiveDarkMode = 19; // Windows 10 1809
    auto darkResult = DwmSetWindowAttribute(handle, DWMWA_USE_IMMERSIVE_DARK_MODE, &darkFrame, sizeof(darkFrame));
    if (FAILED(darkResult))
        darkResult = DwmSetWindowAttribute(handle, legacyImmersiveDarkMode, &darkFrame, sizeof(darkFrame));

    const auto setColor = [handle](DWORD attribute, const QColor &color) {
        const auto rgb = RGB(color.red(), color.green(), color.blue());
        return DwmSetWindowAttribute(handle, attribute, &rgb, sizeof(rgb));
    };
    const auto captionResult = setColor(DWMWA_CAPTION_COLOR, caption);
    if (SUCCEEDED(captionResult)) {
        setColor(DWMWA_TEXT_COLOR, text);
        setColor(DWMWA_BORDER_COLOR, border);
    }

    if (dark && (SUCCEEDED(captionResult) || SUCCEEDED(darkResult))) {
        const QIcon symbol(":/samaya-symbol.svg");
        QIcon icon;
        for (const int size : {16, 20, 24, 32, 48, 64}) {
            auto pixmap = symbol.pixmap(size, size);
            QPainter painter(&pixmap);
            painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
            painter.fillRect(pixmap.rect(), text);
            painter.end();
            icon.addPixmap(pixmap);
        }
        window->setIcon(icon);
    } else {
        window->setIcon(QGuiApplication::windowIcon());
    }

    if (SUCCEEDED(captionResult))
        RedrawWindow(handle, nullptr, nullptr, RDW_INVALIDATE | RDW_FRAME);
    else if (SUCCEEDED(darkResult))
        SetWindowPos(handle, nullptr, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER);
}

bool Desktop::reducedMotion() const
{
    BOOL enabled = TRUE;
    return SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0) && !enabled;
}
