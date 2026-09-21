#include "VlcVideoItem.h"

#include <QDebug>
#include <QFileInfo>
#include <QMetaObject>
#include <QMutexLocker>
#include <QPainter>

#include <cstring>

VlcVideoItem::VlcVideoItem(QQuickItem* parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(false);
    setOpaquePainting(true);
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

    libvlc_media_t* media = nullptr;

    QFileInfo fileInfo(source);
    if (fileInfo.exists() && fileInfo.isFile())
    {
        const QByteArray absolutePath = fileInfo.absoluteFilePath().toUtf8();
        media = libvlc_media_new_path(m_vlc, absolutePath.constData());
        qInfo() << "Minitiger VLC opening local file:" << fileInfo.absoluteFilePath();
    }
    else
    {
        const QByteArray location = source.toUtf8();
        media = libvlc_media_new_location(m_vlc, location.constData());
        qInfo() << "Minitiger VLC opening location:" << source;
    }


    if (!media)
    {
        setError(QStringLiteral("Failed to create libVLC media"));
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
    update();
    return true;
}

void VlcVideoItem::pausePlayback()
{
    if (m_mediaPlayer)
        libvlc_media_player_set_pause(m_mediaPlayer, 1);
}

void VlcVideoItem::resumePlayback()
{
    if (m_mediaPlayer)
        libvlc_media_player_set_pause(m_mediaPlayer, 0);
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

    update();
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

    if (!m_receivedFrame.load(std::memory_order_relaxed))
    {
        painter->setPen(Qt::white);
        painter->drawText(
            boundingRect().adjusted(24, 24, -24, -24),
            Qt::AlignLeft | Qt::AlignTop | Qt::TextWordWrap,
            QStringLiteral("Minitiger libVLC Surface Test\n\n%1").arg(m_status));
    }
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
    item->m_receivedFrame.store(true, std::memory_order_relaxed);
    QMetaObject::invokeMethod(item, [item]() {
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
    // not a reliable alpha channel. QImage::Format_ARGB32 can therefore make
    // valid VLC frames fully transparent. RGB32 intentionally ignores alpha.
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
