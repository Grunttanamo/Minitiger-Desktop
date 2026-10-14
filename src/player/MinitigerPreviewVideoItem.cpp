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
        decoder->setProperty("volume", 0);
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
