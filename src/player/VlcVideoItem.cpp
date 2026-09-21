#include "VlcVideoItem.h"

#include <QDebug>
#include <QFileInfo>
#include <QKeyEvent>
#include <QMetaObject>
#include <QMutexLocker>
#include <QPainter>
#include <QUrl>

#include <cstring>

namespace
{
QString formatTimeMs(qint64 value)
{
    if (value < 0)
        value = 0;

    const qint64 totalSeconds = value / 1000;
    const qint64 hours = totalSeconds / 3600;
    const qint64 minutes = (totalSeconds % 3600) / 60;
    const qint64 seconds = totalSeconds % 60;

    if (hours > 0)
        return QStringLiteral("%1:%2:%3")
            .arg(hours)
            .arg(minutes, 2, 10, QLatin1Char('0'))
            .arg(seconds, 2, 10, QLatin1Char('0'));

    return QStringLiteral("%1:%2")
        .arg(minutes)
        .arg(seconds, 2, 10, QLatin1Char('0'));
}

QString stateName(libvlc_state_t state)
{
    switch (state)
    {
    case libvlc_Opening: return QStringLiteral("Opening");
    case libvlc_Buffering: return QStringLiteral("Buffering");
    case libvlc_Playing: return QStringLiteral("Playing");
    case libvlc_Paused: return QStringLiteral("Paused");
    case libvlc_Stopped: return QStringLiteral("Stopped");
    case libvlc_Ended: return QStringLiteral("Ended");
    case libvlc_Error: return QStringLiteral("Error");
    case libvlc_NothingSpecial:
    default:
        return QStringLiteral("Idle");
    }
}
}

VlcVideoItem::VlcVideoItem(QQuickItem* parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(false);
    setOpaquePainting(true);
    setFlag(QQuickItem::ItemIsFocusScope, true);
    setFocus(true);
    qInfo() << "Minitiger VlcVideoItem constructed";
}

VlcVideoItem::~VlcVideoItem()
{
    releasePlayer();

    if (m_vlc)
    {
        libvlc_release(m_vlc);
        m_vlc = nullptr;
    }
}

bool VlcVideoItem::ensureVlc()
{
    if (m_vlc)
        return true;

    const char* args[] = {
        "--no-video-title-show",
        "--no-osd"
    };

    m_vlc = libvlc_new(static_cast<int>(sizeof(args) / sizeof(args[0])), args);
    if (!m_vlc)
    {
        setError(QStringLiteral("libvlc_new failed"));
        return false;
    }

    qInfo() << "Minitiger libVLC initialized:" << libvlc_get_version();
    return true;
}

void VlcVideoItem::releasePlayer()
{
    if (!m_mediaPlayer)
        return;

    libvlc_media_player_stop(m_mediaPlayer);
    libvlc_media_player_release(m_mediaPlayer);
    m_mediaPlayer = nullptr;
}

bool VlcVideoItem::playSource(const QString& source)
{
    if (source.trimmed().isEmpty())
    {
        setError(QStringLiteral("No VLC test source was provided"));
        return false;
    }

    if (!ensureVlc())
        return false;

    releasePlayer();

    {
        QMutexLocker locker(&m_frameMutex);
        m_frame = QImage();
        m_videoWidth = 0;
        m_videoHeight = 0;
    }

    libvlc_media_t* media = nullptr;

    QFileInfo fileInfo(source);
    libvlc_clearerr();

    if (fileInfo.exists() && fileInfo.isFile())
    {
        const QString absolutePath = fileInfo.absoluteFilePath();
        const QUrl fileUrl = QUrl::fromLocalFile(absolutePath);
        const QByteArray location = fileUrl.toEncoded(QUrl::FullyEncoded);

        qInfo() << "Minitiger VLC opening local file:" << absolutePath;
        qInfo() << "Minitiger VLC file URL:" << location;

        media = libvlc_media_new_location(m_vlc, location.constData());
    }
    else
    {
        const QByteArray location = source.toUtf8();
        qInfo() << "Minitiger VLC opening location:" << source;
        media = libvlc_media_new_location(m_vlc, location.constData());
    }

    if (!media)
    {
        const char* vlcError = libvlc_errmsg();
        const QString detail = vlcError
            ? QString::fromUtf8(vlcError)
            : QStringLiteral("no libVLC error text available");

        setError(QStringLiteral("Failed to create libVLC media: %1\nSource: %2")
                     .arg(detail, source));
        return false;
    }

    m_mediaPlayer = libvlc_media_player_new_from_media(media);
    libvlc_media_release(media);

    if (!m_mediaPlayer)
    {
        setError(QStringLiteral("Failed to create libVLC media player"));
        return false;
    }

    libvlc_video_set_callbacks(
        m_mediaPlayer,
        &VlcVideoItem::lockVideo,
        &VlcVideoItem::unlockVideo,
        &VlcVideoItem::displayVideo,
        this);

    libvlc_video_set_format_callbacks(
        m_mediaPlayer,
        &VlcVideoItem::setupVideoFormat,
        &VlcVideoItem::cleanupVideoFormat);

    // Phase 1.2 test default: intentionally start below VLC's full volume.
    // This will later be replaced by Minitiger/Jellyfin's stored device volume.
    libvlc_audio_set_volume(m_mediaPlayer, m_volume);
    libvlc_audio_set_mute(m_mediaPlayer, 0);

    m_status = QStringLiteral("Opening media with libVLC...");
    m_receivedFrame.store(false, std::memory_order_relaxed);
    update();

    const int result = libvlc_media_player_play(m_mediaPlayer);
    if (result != 0)
    {
        setError(QStringLiteral("libVLC failed to start playback"));
        releasePlayer();
        return false;
    }

    m_lastError.clear();
    m_status = QStringLiteral("Playback started - waiting for first video frame...");
    forceActiveFocus();
    update();
    return true;
}

void VlcVideoItem::togglePause()
{
    if (!m_mediaPlayer)
        return;

    const libvlc_state_t state = libvlc_media_player_get_state(m_mediaPlayer);
    if (state == libvlc_Paused)
    {
        resumePlayback();
    }
    else if (state == libvlc_Playing || state == libvlc_Buffering)
    {
        pausePlayback();
    }
}

void VlcVideoItem::pausePlayback()
{
    if (!m_mediaPlayer)
        return;

    libvlc_media_player_set_pause(m_mediaPlayer, 1);
    m_status = QStringLiteral("Paused");
    update();
}

void VlcVideoItem::resumePlayback()
{
    if (!m_mediaPlayer)
        return;

    libvlc_media_player_set_pause(m_mediaPlayer, 0);
    m_status = QStringLiteral("Playing");
    update();
}

void VlcVideoItem::stopPlayback()
{
    releasePlayer();

    {
        QMutexLocker locker(&m_frameMutex);
        m_frame = QImage();
        m_videoWidth = 0;
        m_videoHeight = 0;
    }

    m_receivedFrame.store(false, std::memory_order_relaxed);
    m_status = QStringLiteral("Stopped");
    update();
}

void VlcVideoItem::seekTo(qint64 position)
{
    if (!m_mediaPlayer)
        return;

    const qint64 length = durationMs();
    if (position < 0)
        position = 0;
    if (length > 0 && position > length)
        position = length;

    libvlc_media_player_set_time(m_mediaPlayer, static_cast<libvlc_time_t>(position));
    m_status = QStringLiteral("Seek: %1").arg(formatTimeMs(position));
    update();
}

void VlcVideoItem::seekRelative(qint64 deltaMs)
{
    seekTo(positionMs() + deltaMs);
}

qint64 VlcVideoItem::positionMs() const
{
    if (!m_mediaPlayer)
        return 0;

    return static_cast<qint64>(libvlc_media_player_get_time(m_mediaPlayer));
}

qint64 VlcVideoItem::durationMs() const
{
    if (!m_mediaPlayer)
        return 0;

    return static_cast<qint64>(libvlc_media_player_get_length(m_mediaPlayer));
}

void VlcVideoItem::setVolume(int value)
{
    if (value < 0)
        value = 0;
    if (value > 100)
        value = 100;

    m_volume = value;

    if (m_mediaPlayer)
        libvlc_audio_set_volume(m_mediaPlayer, m_volume);

    m_status = QStringLiteral("Volume: %1%").arg(m_volume);
    update();
}

int VlcVideoItem::volume() const
{
    if (!m_mediaPlayer)
        return m_volume;

    const int current = libvlc_audio_get_volume(m_mediaPlayer);
    return current >= 0 ? current : m_volume;
}

void VlcVideoItem::setMuted(bool isMuted)
{
    if (m_mediaPlayer)
        libvlc_audio_set_mute(m_mediaPlayer, isMuted ? 1 : 0);

    m_status = isMuted ? QStringLiteral("Muted") : QStringLiteral("Unmuted");
    update();
}

bool VlcVideoItem::muted() const
{
    if (!m_mediaPlayer)
        return false;

    return libvlc_audio_get_mute(m_mediaPlayer) == 1;
}

QString VlcVideoItem::controlOverlayText() const
{
    const QString state = m_mediaPlayer
        ? stateName(libvlc_media_player_get_state(m_mediaPlayer))
        : QStringLiteral("Idle");

    return QStringLiteral(
        "Minitiger libVLC · Phase 1.2\n"
        "%1  ·  %2 / %3  ·  Volume %4%%%5\n"
        "Space Pause/Play   ←/→ Seek 10s   ↑/↓ Volume 5   M Mute")
        .arg(state)
        .arg(formatTimeMs(positionMs()))
        .arg(formatTimeMs(durationMs()))
        .arg(volume())
        .arg(muted() ? QStringLiteral(" · MUTED") : QString());
}

void VlcVideoItem::paint(QPainter* painter)
{
    painter->fillRect(boundingRect(), Qt::black);

    QMutexLocker locker(&m_frameMutex);
    if (m_frame.isNull())
    {
        painter->setPen(Qt::white);
        painter->drawText(
            boundingRect().adjusted(24, 24, -24, -24),
            Qt::AlignLeft | Qt::AlignTop | Qt::TextWordWrap,
            QStringLiteral("Minitiger libVLC Surface Test\n\n%1").arg(m_status));
        return;
    }

    const QSizeF sourceSize(m_frame.width(), m_frame.height());
    QSizeF targetSize = sourceSize;
    targetSize.scale(boundingRect().size(), Qt::KeepAspectRatio);

    const QRectF target(
        (width() - targetSize.width()) / 2.0,
        (height() - targetSize.height()) / 2.0,
        targetSize.width(),
        targetSize.height());

    painter->drawImage(target, m_frame);

    const QRectF overlayRect(16, 16, qMin<qreal>(650, width() - 32), 72);
    painter->fillRect(overlayRect, QColor(0, 0, 0, 170));
    painter->setPen(Qt::white);
    painter->drawText(
        overlayRect.adjusted(12, 8, -12, -8),
        Qt::AlignLeft | Qt::AlignVCenter | Qt::TextWordWrap,
        controlOverlayText());

    if (!m_receivedFrame.load(std::memory_order_relaxed))
    {
        painter->drawText(
            boundingRect().adjusted(24, 104, -24, -24),
            Qt::AlignLeft | Qt::AlignTop | Qt::TextWordWrap,
            m_status);
    }
}

void VlcVideoItem::keyPressEvent(QKeyEvent* event)
{
    if (!m_mediaPlayer)
    {
        QQuickPaintedItem::keyPressEvent(event);
        return;
    }

    switch (event->key())
    {
    case Qt::Key_Space:
        if (!event->isAutoRepeat())
            togglePause();
        event->accept();
        return;

    case Qt::Key_Left:
        seekRelative(-10000);
        event->accept();
        return;

    case Qt::Key_Right:
        seekRelative(10000);
        event->accept();
        return;

    case Qt::Key_Up:
        setVolume(volume() + 5);
        event->accept();
        return;

    case Qt::Key_Down:
        setVolume(volume() - 5);
        event->accept();
        return;

    case Qt::Key_M:
        if (!event->isAutoRepeat())
            setMuted(!muted());
        event->accept();
        return;

    default:
        break;
    }

    QQuickPaintedItem::keyPressEvent(event);
}

void* VlcVideoItem::lockVideo(void* opaque, void** planes)
{
    auto* item = static_cast<VlcVideoItem*>(opaque);
    item->m_frameMutex.lock();

    if (item->m_frame.isNull())
    {
        item->m_frameMutex.unlock();
        *planes = nullptr;
        return nullptr;
    }

    *planes = item->m_frame.bits();
    return item;
}

void VlcVideoItem::unlockVideo(void* opaque, void* picture, void* const* planes)
{
    Q_UNUSED(picture);
    Q_UNUSED(planes);

    auto* item = static_cast<VlcVideoItem*>(opaque);
    item->m_frameMutex.unlock();
}

void VlcVideoItem::displayVideo(void* opaque, void* picture)
{
    Q_UNUSED(picture);

    auto* item = static_cast<VlcVideoItem*>(opaque);
    const bool firstFrame = !item->m_receivedFrame.exchange(true, std::memory_order_relaxed);

    QMetaObject::invokeMethod(item, [item, firstFrame]() {
        if (firstFrame)
            item->m_status = QStringLiteral("Receiving VLC video frames");
        item->update();
    }, Qt::QueuedConnection);
}

unsigned VlcVideoItem::setupVideoFormat(void** opaque,
                                       char* chroma,
                                       unsigned* width,
                                       unsigned* height,
                                       unsigned* pitches,
                                       unsigned* lines)
{
    auto* item = static_cast<VlcVideoItem*>(*opaque);

    // RV32 is VLC's native 32-bit RGB format. Its fourth byte is padding,
    // not a reliable alpha channel. RGB32 intentionally ignores alpha.
    std::memcpy(chroma, "RV32", 4);

    {
        QMutexLocker locker(&item->m_frameMutex);
        item->m_videoWidth = *width;
        item->m_videoHeight = *height;
        item->m_frame = QImage(
            static_cast<int>(*width),
            static_cast<int>(*height),
            QImage::Format_RGB32);

        if (item->m_frame.isNull())
        {
            item->setError(QStringLiteral("Failed to allocate VLC video frame buffer"));
            return 0;
        }

        item->m_frame.fill(Qt::black);
        *pitches = static_cast<unsigned>(item->m_frame.bytesPerLine());
        *lines = *height;
    }

    qInfo() << "Minitiger VLC video format:"
            << *width << "x" << *height
            << "pitch" << *pitches;

    return 1;
}

void VlcVideoItem::cleanupVideoFormat(void* opaque)
{
    auto* item = static_cast<VlcVideoItem*>(opaque);
    QMutexLocker locker(&item->m_frameMutex);
    item->m_frame = QImage();
    item->m_videoWidth = 0;
    item->m_videoHeight = 0;
}

void VlcVideoItem::setError(const QString& error)
{
    m_lastError = error;
    m_status = QStringLiteral("ERROR: %1").arg(error);
    QMetaObject::invokeMethod(this, [this]() { update(); }, Qt::QueuedConnection);
    qWarning() << "Minitiger VLC:" << error;
}
