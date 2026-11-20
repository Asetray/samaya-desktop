#include "desktop.h"
#include <QApplication>
#include <QFileInfo>
#include <QFontDatabase>
#include <QIcon>
#include <QPainter>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSvgRenderer>
#include <QTimer>

int cleanLegacy();

class Symbols final : public QQuickImageProvider {
public:
    Symbols() : QQuickImageProvider(QQuickImageProvider::Image) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override {
        const auto parts = id.split('/');
        const auto name = parts.value(0);
        auto path = ":/assets/upstream/" + name + ".svg";
        if (!QFileInfo::exists(path)) path = ":/" + name + ".svg";
        QSvgRenderer svg(path);
        const auto dims = !requested.isEmpty() ? requested : svg.defaultSize().expandedTo({16,16});
        *size = dims;
        QImage result(dims, QImage::Format_ARGB32_Premultiplied);
        result.fill(Qt::transparent);
        QPainter painter(&result);
        svg.render(&painter);
        if (parts.size() > 1) {
            painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
            painter.fillRect(result.rect(), QColor("#" + parts.at(1)));
        }
        return result;
    }
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    app.setOrganizationName("Samaya");
    app.setApplicationName("samaya-desktop");
    app.setApplicationVersion(SAMAYA_VERSION);
    app.setWindowIcon(QIcon(":/samaya-symbol.svg"));
    const auto args = app.arguments();
    if (args.contains("--clean-legacy")) return cleanLegacy();
    const auto option = [&args](const QString &key) {
        const auto i = args.indexOf(key);
        return i < 0 ? QString{} : args.value(i + 1);
    };
    QFontDatabase::addApplicationFont(app.applicationDirPath() + "/fonts/NotoSansSC.ttf");
    QQuickStyle::setStyle("Basic");
    QQmlApplicationEngine engine;
    Desktop desktop(&engine, option("--settings-file"));
    engine.rootContext()->setContextProperty("desktop", &desktop);
    engine.addImageProvider("symbols", new Symbols);
    engine.load(QUrl("qrc:/qml/Main.qml"));
    if (engine.rootObjects().isEmpty()) return 2;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    const auto output = option("--smoke-test");
    if (!output.isEmpty()) QTimer::singleShot(1800, window, [window,output] {
        QCoreApplication::exit(window->grabWindow().save(output) ? 0 : 1);
    });
    const auto result = app.exec();
    delete window;
    return result;
}