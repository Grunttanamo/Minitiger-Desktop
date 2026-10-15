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
        // Match the old HTML object-fit:cover instead of letterboxing a
        // 16:9 trailer in the ultra-wide home banner.
        decoder->setProperty("panscan", 1.0);
        decoder->setProperty("loop-file", "no");
        decoder->setProperty("keep-open", "no");
        decoder->setProperty("pause", false);
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
    // A "stop" and end-of-file can leave MPV paused for the next load.
    // Execute all operations serially on the dedicated MPV worker.
    m_requestedUrl = url;
    mpvController()->command(QStringList() << "stop");
    mpvController()->setProperty("loop-file", loop ? "inf" : "no");
    mpvController()->setProperty("pause", false);
    mpvController()->command(QStringList() << "loadfile" << url << "replace");
    mpvController()->setProperty("pause", false);
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
        .arg(property("path")).arg(property("vid")).arg(property("aid"))
        .arg(property("video-codec")).arg(property("audio-codec"))
        .arg(property("video-params/w")).arg(property("video-params/h"))
        .arg(property("hwdec-current")).arg(property("mute"))
        .arg(property("volume")).arg(property("pause")).arg(property("eof-reached"));
}

bool MinitigerPreviewVideoItem::previewHasVideo() const
{
    if (!m_ready || m_requestedUrl.isEmpty())
        return false;
    auto* controller = const_cast<MinitigerPreviewVideoItem*>(this)->mpvController();
    if (!controller || !controller->mpv())
        return false;
    auto* handle = controller->mpv();
    // Video parameters alone may still belong to the LAST trailer, especially
    // if the old player kept its final frame at EOF. Never acknowledge that.
    char* path = mpv_get_property_string(handle, "path");
    const bool currentFile = path && QString::fromUtf8(path) == m_requestedUrl;
    if (path) mpv_free(path);
    if (!currentFile) return false;
    int paused = 1;
    int idle = 1;
    if (mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &paused) < 0 || paused)
        return false;
    if (mpv_get_property(handle, "core-idle", MPV_FORMAT_FLAG, &idle) < 0 || idle)
        return false;
    int64_t width = 0;
    int64_t height = 0;
    double seconds = 0.0;
    return mpv_get_property(handle, "video-params/w", MPV_FORMAT_INT64, &width) >= 0
        && mpv_get_property(handle, "video-params/h", MPV_FORMAT_INT64, &height) >= 0
        && mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &seconds) >= 0
        && width > 0 && height > 0 && seconds > 0.04;
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
    m_requestedUrl.clear();
    if (mpvController()) {
        mpvController()->command(QStringList() << "stop");
        mpvController()->setProperty("pause", false);
    }
}

void MinitigerPreviewVideoItem::setPreviewMuted(bool muted)
{
    if (mpvController())
        mpvController()->setProperty("mute", muted);
}

void MinitigerPreviewVideoItem::setPreviewSuspended(bool suspended)
{
    // Pause BOTH audio and video during Qt WebEngine scroll compositing.
    // Keep the current source decoded and resume it without reloading.
    if (mpvController())
        mpvController()->setProperty("pause", suspended);
}
