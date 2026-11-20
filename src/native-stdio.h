#pragma once

#include <QByteArray>
#include <QProcess>
#include <QQueue>
#include <qt_windows.h>

class NativeStdio {
public:
    ~NativeStdio() { close(); }
    bool open();
    void installHandles(QProcess::CreateProcessArguments *args) const;
    void closeChildHandles();
    void closeInput();
    void close();
    bool send(const QByteArray &message);
    bool pump(QByteArray &received);

private:
    struct Pipe {
        ~Pipe();
        bool open(bool input);
        void closeChild();
        void close();

        HANDLE parent = INVALID_HANDLE_VALUE;
        HANDLE child = INVALID_HANDLE_VALUE;
        OVERLAPPED io{};
        bool pending = false;
    };
    bool writeNext();
    bool readNext(QByteArray &received);

    Pipe input_;
    Pipe output_;
    HANDLE errorStream_ = INVALID_HANDLE_VALUE;
    QQueue<QByteArray> outbound_;
    QByteArray readBuffer_ = QByteArray(64 * 1024, Qt::Uninitialized);
    qsizetype written_ = 0;
};
