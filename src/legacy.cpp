#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSettings>
#include <qt_windows.h>

int cleanLegacyFiles(const QDir &root)
{
    QFile manifest(":/packaging/legacy-0.2.sha256");
    if (!manifest.open(QIODevice::ReadOnly)) return 1;
    QStringList dirs;
    bool ok = true;
    while (!manifest.atEnd()) {
        const auto row = manifest.readLine().trimmed();
        const auto relative = QString::fromUtf8(row.sliced(66));
        if (!relative.startsWith("codex/") || relative.contains("..")) return 1;
        const auto path = root.absoluteFilePath(relative);
        if (!QFileInfo::exists(path)) continue;
        auto child = path;
        while (child != root.absolutePath()) {
            const auto attr = GetFileAttributesW(reinterpret_cast<LPCWSTR>(child.utf16()));
            if (attr == INVALID_FILE_ATTRIBUTES || (attr & FILE_ATTRIBUTE_REPARSE_POINT)) return 1;
            child = QFileInfo(child).absolutePath();
            if (child != root.absolutePath() && !dirs.contains(child)) dirs.append(child);
        }
        QFile file(path);
        QCryptographicHash hash(QCryptographicHash::Sha256);
        if (!file.open(QIODevice::ReadOnly) || !hash.addData(&file)) { ok = false; continue; }
        file.close();
        if (hash.result().toHex() == row.first(64) && !file.remove()) ok = false;
    }
    std::sort(dirs.begin(), dirs.end(), [](const QString &a,const QString &b){ return a.size() > b.size(); });
    for (const auto &dir : dirs) QDir().rmdir(dir);
    return ok ? 0 : 2;
}
int cleanLegacy()
{
    const QDir root(QCoreApplication::applicationDirPath());
    QSettings reg("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\SamayaDesktop", QSettings::NativeFormat);
    if (reg.value("DisplayVersion").toString() != "0.2.0" ||
        QDir(reg.value("InstallLocation").toString()) != root) return 1;
    return cleanLegacyFiles(root);
}
