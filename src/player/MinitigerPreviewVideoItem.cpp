#include "MinitigerPreviewVideoItem.h"
#include <MpvController>
#include <QStringList>
#include <QUrl>

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
        decoder->setProperty("loop-file", "inf");
        m_ready = true;
        emit readyForPreviewChanged();
    });
}

bool MinitigerPreviewVideoItem::playPreview(const QString& url)
{
    if (!m_ready || !mpvController())
        return false;
    const QUrl parsed(url);
    if (!parsed.isValid() || (parsed.scheme() != "https" && parsed.scheme() != "http"))
        return false;
    mpvController()->command(QStringList() << "loadfile" << url << "replace");
    return true;
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
