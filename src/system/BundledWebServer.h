#ifndef BUNDLEDWEBSERVER_H
#define BUNDLEDWEBSERVER_H

#include <QObject>
#include <QTcpServer>
#include <QUrl>

class QTcpSocket;

class BundledWebServer : public QObject
{
    Q_OBJECT

public:
    explicit BundledWebServer(QObject* parent = nullptr);

    bool start();
    QUrl baseUrl() const;
    bool isRunning() const { return m_server.isListening(); }

private:
    void handleConnection();
    void handleRequest(QTcpSocket* socket);
    QByteArray mimeTypeForPath(const QString& path) const;
    QByteArray responseForStatus(int statusCode, const QByteArray& body, const QByteArray& contentType) const;

    QTcpServer m_server;
};

#endif // BUNDLEDWEBSERVER_H
