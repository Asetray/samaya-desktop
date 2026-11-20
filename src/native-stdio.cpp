#include "native-stdio.h"

#include <QUuid>

namespace {
void closeHandle(HANDLE &handle)
{
    if (handle == INVALID_HANDLE_VALUE) return;
    CloseHandle(handle);
    handle = INVALID_HANDLE_VALUE;
}
}

NativeStdio::Pipe::~Pipe()
{
    close();
}

bool NativeStdio::Pipe::open(bool input)
{
    const auto name = QStringLiteral("\\\\.\\pipe\\samaya-") + QUuid::createUuid().toString(QUuid::WithoutBraces);
    const auto path = reinterpret_cast<LPCWSTR>(name.utf16());
    constexpr DWORD capacity = 64 * 1024;
    const auto access = input ? PIPE_ACCESS_OUTBOUND : PIPE_ACCESS_INBOUND;
    parent = CreateNamedPipeW(path, access | FILE_FLAG_FIRST_PIPE_INSTANCE | FILE_FLAG_OVERLAPPED,
                              PIPE_TYPE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1,
                              input ? capacity : 0, input ? 0 : capacity, 0, nullptr);
    if (parent == INVALID_HANDLE_VALUE) return false;
    // Codex and its runtime use synchronous standard handles. Only the client ends use overlapped I/O.
    SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
    child = CreateFileW(path, input ? GENERIC_READ : GENERIC_WRITE, 0, &attributes, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (child == INVALID_HANDLE_VALUE) return false;
    io.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!io.hEvent) return false;
    if (ConnectNamedPipe(parent, &io)) return true;
    const auto error = GetLastError();
    if (error != ERROR_IO_PENDING) return error == ERROR_PIPE_CONNECTED;
    DWORD transferred = 0;
    return GetOverlappedResult(parent, &io, &transferred, TRUE) != FALSE;
}

void NativeStdio::Pipe::closeChild()
{
    closeHandle(child);
}

void NativeStdio::Pipe::close()
{
    if (pending) {
        CancelIoEx(parent, &io);
        DWORD count = 0;
        GetOverlappedResult(parent, &io, &count, TRUE);
        pending = false;
    }
    closeChild();
    closeHandle(parent);
    if (io.hEvent) CloseHandle(io.hEvent);
    io = {};
}

bool NativeStdio::open()
{
    close();
    if (!input_.open(true) || !output_.open(false)) return false;
    SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
    errorStream_ = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                               &attributes, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    return errorStream_ != INVALID_HANDLE_VALUE;
}

void NativeStdio::installHandles(QProcess::CreateProcessArguments *args) const
{
    args->flags = (args->flags & ~DWORD(CREATE_NEW_CONSOLE)) | CREATE_NO_WINDOW;
    args->inheritHandles = true;
    args->startupInfo->dwFlags |= STARTF_USESTDHANDLES;
    args->startupInfo->hStdInput = input_.child;
    args->startupInfo->hStdOutput = output_.child;
    args->startupInfo->hStdError = errorStream_;
}

void NativeStdio::closeChildHandles()
{
    input_.closeChild();
    output_.closeChild();
    closeHandle(errorStream_);
}

void NativeStdio::closeInput()
{
    input_.close();
    outbound_.clear();
    written_ = 0;
}

void NativeStdio::close()
{
    closeChildHandles();
    closeInput();
    output_.close();
}

bool NativeStdio::send(const QByteArray &message)
{
    if (input_.parent == INVALID_HANDLE_VALUE) return false;
    outbound_.enqueue(message);
    return true;
}

bool NativeStdio::pump(QByteArray &received)
{
    return writeNext() && readNext(received);
}

bool NativeStdio::writeNext()
{
    if (outbound_.isEmpty()) return true;
    const auto &message = outbound_.head();
    DWORD count = 0;
    if (input_.pending) {
        if (!GetOverlappedResult(input_.parent, &input_.io, &count, FALSE))
            return GetLastError() == ERROR_IO_INCOMPLETE;
        input_.pending = false;
    } else if (!WriteFile(input_.parent, message.constData() + written_, DWORD(message.size() - written_), &count, &input_.io)) {
        input_.pending = GetLastError() == ERROR_IO_PENDING;
        return input_.pending;
    }
    written_ += count;
    if (written_ == message.size()) {
        outbound_.dequeue();
        written_ = 0;
    }
    return count != 0;
}

bool NativeStdio::readNext(QByteArray &received)
{
    DWORD count = 0;
    if (output_.pending) {
        if (!GetOverlappedResult(output_.parent, &output_.io, &count, FALSE))
            return GetLastError() == ERROR_IO_INCOMPLETE;
        output_.pending = false;
    } else if (!ReadFile(output_.parent, readBuffer_.data(), DWORD(readBuffer_.size()), &count, &output_.io)) {
        output_.pending = GetLastError() == ERROR_IO_PENDING;
        return output_.pending;
    }
    received.append(readBuffer_.constData(), count);
    return true;
}
