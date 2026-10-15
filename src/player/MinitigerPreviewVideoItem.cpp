#include "MinitigerPreviewVideoItem.h"
#include <MpvController>
#include <QStringList>
#include <QUrl>
#include <mpv/client.h>

MinitigerPreviewVideoItem::MinitigerPreviewVideoItem(QQuickItem* parent)
    : MpvAbstractItem(parent)
{
    Q_EMIT setProperty("vo", "libmpv");
#ifdef Q_OS_WIN32
    Q_EMIT setProperty("gpu-api", "opengl");
    Q_EMIT setProperty("opengl-es", "no");
#endif
    connect(this, &MpvAbstractItem::ready, this, [this]() {
        auto* decoder = mpvController();
        if (!decoder)
            return;
        decoder->setProperty("mute", true);
        decoder->setProperty("volume", 100);
        decoder->setProperty("osd-level", 0);
        decoder->setProperty("ytdl", false);
        decoder->setProperty("hwdec", "auto-safe");
        decoder->setProperty("loop-file", "no");
        decoder->setProperty("keep-open", "yes");
        m_ready = true;
        emit readyForPreviewChanged();
    });
}

bool MinitigerPreviewVideoItem::playPreview(const QString& url, bool loop)
{
    if (!m_ready || !mpvController())
        return false;
    const QUrl parsed(url);
    if (!parsed.isValid() || (parsed.scheme() != "https" && parsed.scheme() != "http"))
        return false;
    mpvController()->setProperty("loop-file", loop ? "inf" : "no");
    mpvController()->command(QStringList() << "loadfile" << url << "replace");
    return true;
}

QString MinitigerPreviewVideoItem::previewStatus() const
{
    auto* controller = const_cast<MinitigerPreviewVideoItem*>(this)->mpvController();
    if (!controller || !controller->mpv()) return QStringLiteral("MPV: not initialized");
    auto* h = controller->mpv();
    auto property = [h](const char* key) -> QString {
        char* value = mpv_get_property_string(h, key);
        if (!value) return QStringLiteral("-");
        QString result = QString::fromUtf8(value);
        mpv_free(value);
        return result;
    };
    return QStringLiteral("MPV path: %1\\nVideo track: %2\\nAudio track: %3\\n"
                          "Video codec: %4\\nAudio codec: %5\\nVideo width: %6\\n"
                          "Video height: %7\\nHW decoder: %8\\nMuted: %9\\n"
                          "Volume: %10\\nPaused: %11\\nEOF: %12")
        .arg(property("path"), property("vid"), property("aid"),
             property("video-codec"), property("audio-codec"),
             property("video-params/w"), property("video-params/h"),
             property("hwdec-current"), property("mute"),
             property("volume"), property("pause"), property("eof-reached"));
}

bool MinitigerPreviewVideoItem::previewEnded() const
{
    auto* controller = const_cast<MinitigerPreviewVideoItem*>(this)->mpvController();
    if (!controller) return false;
    int ended = 0;
    return mpv_get_property(controller->mpv(), "eof-reached", MPV_FORMAT_FLAG, &ended) >= 0 && ended;
}

void MinitigerPreviewVideoItem::stopPreview()
{
    if (mpvController())
        mpvController()->command(QStringList() << "stop");
}

void MinitigerPreviewVideoItem::setPreviewMuted(bool muted)
{
    if (mpvController())
        mpvController()->setProperty("mute", muted);
}
