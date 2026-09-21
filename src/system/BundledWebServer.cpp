#include "BundledWebServer.h"

#include <QDebug>
#include <QFile>
#include <QHostAddress>
#include <QPointer>
#include <QTcpSocket>
#include <QUrl>

BundledWebServer::BundledWebServer(QObject* parent)
    : QObject(parent)
{
    connect(&m_server, &QTcpServer::newConnection, this, &BundledWebServer::handleConnection);
}

bool BundledWebServer::start()
{
    if (m_server.isListening())
        return true;

    if (!m_server.listen(QHostAddress::LocalHost, 0))
    {
        qCritical() << "Minitiger bundled web server failed to listen:"
                    << m_server.errorString();
        return false;
    }

    qInfo() << "Minitiger bundled web server listening at" << baseUrl().toString();
    return true;
}

QUrl BundledWebServer::baseUrl() const
{
    if (!m_server.isListening())
        return {};

    return QUrl(QStringLiteral("http://127.0.0.1:%1/").arg(m_server.serverPort()));
}

void BundledWebServer::handleConnection()
{
    while (QTcpSocket* socket = m_server.nextPendingConnection())
    {
        socket->setParent(this);

        connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
            handleRequest(socket);
        });

        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
    }
}

void BundledWebServer::handleRequest(QTcpSocket* socket)
{
    if (!socket || !socket->canReadLine())
        return;

    const QByteArray requestLine = socket->readLine().trimmed();
    const QList<QByteArray> parts = requestLine.split(' ');

    if (parts.size() < 2)
    {
        socket->write(responseForStatus(400, "Bad Request", "text/plain; charset=utf-8"));
        socket->disconnectFromHost();
        return;
    }

    const QByteArray method = parts.at(0);
    if (method != "GET" && method != "HEAD")
    {
        socket->write(responseForStatus(405, "Method Not Allowed", "text/plain; charset=utf-8"));
        socket->disconnectFromHost();
        return;
    }

    QByteArray rawTarget = parts.at(1);
    const int queryIndex = rawTarget.indexOf('?');
    if (queryIndex >= 0)
        rawTarget.truncate(queryIndex);

    const int fragmentIndex = rawTarget.indexOf('#');
    if (fragmentIndex >= 0)
        rawTarget.truncate(fragmentIndex);

    if (rawTarget.isEmpty() || rawTarget == "/")
        rawTarget = "/index.html";

    if (!rawTarget.startsWith('/'))
        rawTarget.prepend('/');

    // Browser requests percent-encode characters in path segments (for
    // example '@' becomes '%40'). The Qt resource aliases contain the actual
    // webpack filenames, so decode the URL path before looking up the resource.
    const QString requestPath = QUrl::fromPercentEncoding(rawTarget);
    QString resourcePath = QStringLiteral(":/web-client/minitiger") + requestPath;

    // Prevent attempts to traverse outside the embedded web root. Perform this
    // check after percent-decoding so encoded traversal attempts are rejected.
    if (requestPath.contains(QStringLiteral("..")))
    {
        socket->write(responseForStatus(403, "Forbidden", "text/plain; charset=utf-8"));
        socket->disconnectFromHost();
        return;
    }

    QFile file(resourcePath);

    // React/Remix routes are client-side. When a navigation path has no
    // corresponding static resource, fall back to the embedded index.html.
    if (!file.exists())
    {
        const QString lastSegment = requestPath.section('/', -1);
        if (!lastSegment.contains('.'))
        {
            resourcePath = QStringLiteral(":/web-client/minitiger/index.html");
            file.setFileName(resourcePath);
        }
    }

    if (!file.exists() || !file.open(QIODevice::ReadOnly))
    {
        qWarning() << "Bundled web resource not found:" << requestPath
                   << "(raw request:" << rawTarget << ")";
        socket->write(responseForStatus(404, "Not Found", "text/plain; charset=utf-8"));
        socket->disconnectFromHost();
        return;
    }

    const QByteArray body = file.readAll();
    const QByteArray contentType = mimeTypeForPath(resourcePath);

    QByteArray response;
    response += "HTTP/1.1 200 OK\r\n";
    response += "Content-Type: " + contentType + "\r\n";
    response += "Content-Length: " + QByteArray::number(body.size()) + "\r\n";
    response += "Cache-Control: no-cache\r\n";
    response += "Access-Control-Allow-Origin: *\r\n";
    response += "Cross-Origin-Resource-Policy: cross-origin\r\n";
    response += "X-Content-Type-Options: nosniff\r\n";
    response += "Connection: close\r\n\r\n";

    socket->write(response);
    if (method != "HEAD")
        socket->write(body);

    socket->disconnectFromHost();
}

QByteArray BundledWebServer::mimeTypeForPath(const QString& path) const
{
    const QString lower = path.toLower();

    if (lower.endsWith(".html")) return "text/html; charset=utf-8";
    if (lower.endsWith(".js") || lower.endsWith(".mjs")) return "text/javascript; charset=utf-8";
    if (lower.endsWith(".css")) return "text/css; charset=utf-8";
    if (lower.endsWith(".json")) return "application/json; charset=utf-8";
    if (lower.endsWith(".svg")) return "image/svg+xml";
    if (lower.endsWith(".png")) return "image/png";
    if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
    if (lower.endsWith(".webp")) return "image/webp";
    if (lower.endsWith(".gif")) return "image/gif";
    if (lower.endsWith(".ico")) return "image/x-icon";
    if (lower.endsWith(".woff2")) return "font/woff2";
    if (lower.endsWith(".woff")) return "font/woff";
    if (lower.endsWith(".ttf")) return "font/ttf";
    if (lower.endsWith(".otf")) return "font/otf";
    if (lower.endsWith(".wasm")) return "application/wasm";
    if (lower.endsWith(".xml")) return "application/xml; charset=utf-8";
    if (lower.endsWith(".txt")) return "text/plain; charset=utf-8";

    return "application/octet-stream";
}

QByteArray BundledWebServer::responseForStatus(
    int statusCode,
    const QByteArray& body,
    const QByteArray& contentType) const
{
    QByteArray reason = "Error";
    if (statusCode == 400) reason = "Bad Request";
    else if (statusCode == 403) reason = "Forbidden";
    else if (statusCode == 404) reason = "Not Found";
    else if (statusCode == 405) reason = "Method Not Allowed";

    QByteArray response;
    response += "HTTP/1.1 " + QByteArray::number(statusCode) + " " + reason + "\r\n";
    response += "Content-Type: " + contentType + "\r\n";
    response += "Content-Length: " + QByteArray::number(body.size()) + "\r\n";
    response += "Cache-Control: no-cache\r\n";
    response += "Connection: close\r\n\r\n";
    response += body;
    return response;
}
