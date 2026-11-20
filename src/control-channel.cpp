#include "control-channel.h"
#include <QCryptographicHash>
#include <QRandomGenerator>
#include <QtEndian>
#include <cstring>

namespace {
constexpr qsizetype maxPayload = 64 * 1024 * 1024;
QByteArray randomBytes(int n)
{
    QByteArray bytes(n, Qt::Uninitialized);
    for (int i = 0; i < n; i += 4) {
        const quint32 word = QRandomGenerator::system()->generate();
        std::memcpy(bytes.data() + i, &word, 4);
    }
    return bytes;
}
}

QByteArray ControlChannel::handshake()
{
    *this = {};
    const auto key = randomBytes(16).toBase64();
    expectedAccept_ = QCryptographicHash::hash(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11", QCryptographicHash::Sha1).toBase64();
    return "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: " + key + "\r\n\r\n";
}

QByteArray ControlChannel::frame(const QByteArray &payload, quint8 opcode)
{
    QByteArray out(1, char(0x80 | opcode));
    const quint64 size = payload.size();
    if (size < 126) out.append(char(0x80 | size));
    else if (size <= 65535) {
        out.append(char(0xfe));
        const auto be = qToBigEndian(quint16(size));
        out.append(reinterpret_cast<const char *>(&be), 2);
    } else {
        out.append(char(0xff));
        const auto be = qToBigEndian(size);
        out.append(reinterpret_cast<const char *>(&be), 8);
    }
    const auto mask = randomBytes(4);
    out.append(mask);
    auto data = payload;
    for (qsizetype i = 0; i < data.size(); ++i) data[i] = char(data[i] ^ mask[i % 4]);
    return out + data;
}

bool ControlChannel::receive(const QByteArray &input, QList<QByteArray> &messages, QList<QByteArray> &controls)
{
    buffer_ += input;
    if (!upgraded_) {
        const auto end = buffer_.indexOf("\r\n\r\n");
        if (end < 0) return buffer_.size() <= 16384;
        if (end > 16384) return false;
        const auto lines = buffer_.first(end).split('\n');
        if (!lines.first().trimmed().startsWith("HTTP/1.1 101 ")) return false;
        bool accept = false, upgrade = false, connection = false;
        for (const auto &line : lines) {
            const auto sep = line.indexOf(':');
            if (sep <= 0) continue;
            const auto key = line.first(sep).trimmed().toLower();
            const auto value = line.sliced(sep + 1).trimmed();
            if (key == "sec-websocket-accept") accept = value == expectedAccept_;
            if (key == "upgrade") upgrade = value.toLower() == "websocket";
            if (key == "connection") for (const auto &token : value.toLower().split(',')) connection |= token.trimmed() == "upgrade";
        }
        if (!accept || !upgrade || !connection) return false;
        buffer_.remove(0, end + 4);
        upgraded_ = true;
    }
    while (buffer_.size() >= 2) {
        const auto flags = quint8(buffer_[0]), lengthByte = quint8(buffer_[1]);
        if ((flags & 0x70) || (lengthByte & 0x80)) return false;
        const auto opcode = flags & 15;
        const bool final = flags & 0x80;
        quint64 size = lengthByte;
        qsizetype header = 2;
        if (size == 126 || size == 127) {
            header += size == 126 ? 2 : 8;
            if (buffer_.size() < header) break;
            size = header == 4 ? qFromBigEndian<quint16>(buffer_.constData() + 2) : qFromBigEndian<quint64>(buffer_.constData() + 2);
        }
        if (size > maxPayload || (opcode >= 8 && (!final || size > 125))) return false;
        if (quint64(buffer_.size() - header) < size) break;
        auto payload = buffer_.sliced(header, qsizetype(size));
        buffer_.remove(0, header + qsizetype(size));
        if (opcode == 8) return false;
        if (opcode == 9) { controls.append(frame(payload, 10)); continue; }
        if (opcode == 10) continue;
        if ((opcode != 0 && opcode != 1 && opcode != 2) || (opcode == 0) != continuing_) return false;
        if (fragmented_.size() + payload.size() > maxPayload) return false;
        fragmented_ += payload;
        continuing_ = !final;
        if (final) { messages.append(std::move(fragmented_)); fragmented_.clear(); }
    }
    return true;
}
