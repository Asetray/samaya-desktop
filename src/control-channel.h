#pragma once

#include <QByteArray>
#include <QList>

// RFC 6455 client framing over the official local app-server proxy.
class ControlChannel {
public:
    QByteArray handshake();
    static QByteArray frame(const QByteArray &payload, quint8 opcode = 1);
    bool receive(const QByteArray &input, QList<QByteArray> &messages, QList<QByteArray> &controls);
    bool upgraded() const { return upgraded_; }
private:
    QByteArray buffer_, fragmented_, expectedAccept_;
    bool upgraded_ = false, continuing_ = false;
};
