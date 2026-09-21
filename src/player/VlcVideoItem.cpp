#include "VlcVideoItem.h"

#include <QDebug>
#include <QFileInfo>
#include <QKeyEvent>
#include <QMetaObject>
#include <QMouseEvent>
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
    setAcceptedMouseButtons(Qt::LeftButton);
    setFocus(true);

    m_pollTimer.setInterval(250);
    connect(&m_pollTimer, &QTimer::timeout, this, [this]() {
        pollPlaybackState();
    });

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
    m_pollTimer.stop();

    if (!m_mediaPlayer)
        return;

    libvlc_media_player_stop(m_mediaPlayer);
    libvlc_media_player_release(m_mediaPlayer);
    m_mediaPlayer = nullptr;
}

bool VlcVideoItem::playSource(const QString& source, qint64 startMilliseconds, bool autoplay, const QString& userAgent)
{
    if (source.trimmed().isEmpty())
    {
        setError(QStringLiteral("No VLC test source was provided"));
        return false;
    }

    if (!ensureVlc())
        return false;

    m_source = source;
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

    if (media && !userAgent.isEmpty())
    {
        const QByteArray option = QStringLiteral(":http-user-agent=%1").arg(userAgent).toUtf8();
        libvlc_media_add_option(media, option.constData());
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
    m_lastPolledState = libvlc_NothingSpecial;
    m_lastDurationMs = -1;
    m_pendingStartMs = qMax<qint64>(0, startMilliseconds);
    m_pendingAutoplay = autoplay;
    m_pendingInitialSeek = m_pendingStartMs > 0 || !m_pendingAutoplay;
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
    m_pollTimer.start();
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

void VlcVideoItem::setPlaybackRate(double rate)
{
    if (!m_mediaPlayer || rate <= 0.0)
        return;

    libvlc_media_player_set_rate(m_mediaPlayer, static_cast<float>(rate));
}

int VlcVideoItem::trackIdForRelativeIndex(libvlc_track_description_t* tracks, int relativeIndex) const
{
    if (relativeIndex <= 0)
        return -1;

    int current = 0;
    for (libvlc_track_description_t* track = tracks; track; track = track->p_next)
    {
        // Subtitle lists can include the synthetic "Disable" entry with id -1.
        if (track->i_id < 0)
            continue;

        ++current;
        if (current == relativeIndex)
            return track->i_id;
    }

    return -1;
}

bool VlcVideoItem::setAudioTrackRelative(int relativeIndex)
{
    if (!m_mediaPlayer || relativeIndex <= 0)
        return false;

    libvlc_track_description_t* tracks = libvlc_audio_get_track_description(m_mediaPlayer);
    const int trackId = trackIdForRelativeIndex(tracks, relativeIndex);

    if (tracks)
        libvlc_track_description_list_release(tracks);

    if (trackId < 0)
    {
        qWarning() << "Minitiger VLC: audio relative track not found:" << relativeIndex;
        return false;
    }

    const int result = libvlc_audio_set_track(m_mediaPlayer, trackId);
    qInfo() << "Minitiger VLC audio track:" << relativeIndex << "-> id" << trackId
            << (result == 0 ? "selected" : "failed");
    return result == 0;
}

bool VlcVideoItem::setSubtitleTrackRelative(int relativeIndex)
{
    if (!m_mediaPlayer)
        return false;

    if (relativeIndex < 0)
    {
        const int result = libvlc_video_set_spu(m_mediaPlayer, -1);
        qInfo() << "Minitiger VLC subtitles disabled"
                << (result == 0 ? "successfully" : "with error");
        return result == 0;
    }

    libvlc_track_description_t* tracks = libvlc_video_get_spu_description(m_mediaPlayer);
    const int trackId = trackIdForRelativeIndex(tracks, relativeIndex);

    if (tracks)
        libvlc_track_description_list_release(tracks);

    if (trackId < 0)
    {
        qWarning() << "Minitiger VLC: subtitle relative track not found:" << relativeIndex;
        return false;
    }

    const int result = libvlc_video_set_spu(m_mediaPlayer, trackId);
    qInfo() << "Minitiger VLC subtitle track:" << relativeIndex << "-> id" << trackId
            << (result == 0 ? "selected" : "failed");
    return result == 0;
}

bool VlcVideoItem::addExternalSubtitle(const QString& source)
{
    if (!m_mediaPlayer || source.trimmed().isEmpty())
        return false;

    QUrl subtitleUrl;
    QFileInfo localFile(source);

    if (localFile.exists() && localFile.isFile())
    {
        subtitleUrl = QUrl::fromLocalFile(localFile.absoluteFilePath());
    }
    else
    {
        subtitleUrl = QUrl(source);

        if (subtitleUrl.isRelative())
        {
            const QUrl mediaUrl(m_source);
            subtitleUrl = mediaUrl.resolved(subtitleUrl);
        }
    }

    const QByteArray encoded = subtitleUrl.toEncoded(QUrl::FullyEncoded);
    const int result = libvlc_media_player_add_slave(
        m_mediaPlayer,
        libvlc_media_slave_type_subtitle,
        encoded.constData(),
        true);

    qInfo() << "Minitiger VLC external subtitle:" << encoded
            << (result == 0 ? "added" : "failed");
    return result == 0;
}

void VlcVideoItem::pollPlaybackState()
{
    if (!m_mediaPlayer)
        return;

    const libvlc_state_t state = libvlc_media_player_get_state(m_mediaPlayer);

    const qint64 position = positionMs();
    const qint64 duration = durationMs();

    if (duration > 0 && duration != m_lastDurationMs)
    {
        m_lastDurationMs = duration;
        emit durationChanged(duration);
    }

    if (position >= 0)
        emit positionChanged(position);

    if (state == libvlc_Playing && m_pendingInitialSeek)
    {
        if (m_pendingStartMs > 0)
            libvlc_media_player_set_time(m_mediaPlayer, static_cast<libvlc_time_t>(m_pendingStartMs));

        if (!m_pendingAutoplay)
            libvlc_media_player_set_pause(m_mediaPlayer, 1);

        m_pendingInitialSeek = false;
    }

    if (state != m_lastPolledState)
    {
        switch (state)
        {
        case libvlc_Playing:
            emit playbackStarted();
            break;
        case libvlc_Paused:
            emit playbackPaused();
            break;
        case libvlc_Ended:
            emit playbackFinished();
            m_pollTimer.stop();
            break;
        case libvlc_Error:
        {
            const char* vlcError = libvlc_errmsg();
            const QString message = vlcError
                ? QString::fromUtf8(vlcError)
                : QStringLiteral("libVLC playback error");
            emit playbackError(message);
            m_pollTimer.stop();
            break;
        }
        default:
            break;
        }

        m_lastPolledState = state;
    }

    update();
}

QString VlcVideoItem::controlOverlayText() const
{
    const QString state = m_mediaPlayer
        ? stateName(libvlc_media_player_get_state(m_mediaPlayer))
        : QStringLiteral("Idle");

    return QStringLiteral("%1  ·  %2 / %3  ·  Volume %4%%5")
        .arg(state)
        .arg(formatTimeMs(positionMs()))
        .arg(formatTimeMs(durationMs()))
        .arg(volume())
        .arg(muted() ? QStringLiteral(" · MUTED") : QString());
}

QRectF VlcVideoItem::controlBarRect() const
{
    const qreal margin = 24.0;
    const qreal barHeight = 94.0;
    return QRectF(
        margin,
        qMax<qreal>(margin, height() - barHeight - margin),
        qMax<qreal>(0.0, width() - (margin * 2.0)),
        barHeight);
}

QRectF VlcVideoItem::progressRect() const
{
    const QRectF bar = controlBarRect();
    return QRectF(bar.left() + 18.0, bar.top() + 15.0, qMax<qreal>(0.0, bar.width() - 36.0), 8.0);
}

QRectF VlcVideoItem::playButtonRect() const
{
    const QRectF bar = controlBarRect();
    return QRectF(bar.left() + 18.0, bar.top() + 38.0, 54.0, 40.0);
}

QRectF VlcVideoItem::backButtonRect() const
{
    const QRectF play = playButtonRect();
    return QRectF(play.right() + 10.0, play.top(), 54.0, 40.0);
}

QRectF VlcVideoItem::forwardButtonRect() const
{
    const QRectF back = backButtonRect();
    return QRectF(back.right() + 10.0, back.top(), 54.0, 40.0);
}

QRectF VlcVideoItem::muteButtonRect() const
{
    const QRectF bar = controlBarRect();
    return QRectF(bar.right() - 214.0, bar.top() + 38.0, 72.0, 40.0);
}

QRectF VlcVideoItem::volumeDownButtonRect() const
{
    const QRectF mute = muteButtonRect();
    return QRectF(mute.right() + 10.0, mute.top(), 40.0, 40.0);
}

QRectF VlcVideoItem::volumeUpButtonRect() const
{
    const QRectF down = volumeDownButtonRect();
    return QRectF(down.right() + 10.0, down.top(), 40.0, 40.0);
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

    // Phase 1.5a quality path:
    // The VLC callback gives us a native-resolution QImage. QPainter otherwise
    // may use a fast nearest-neighbour style transform when that frame needs to
    // be resized to the Qt Quick surface, which is especially visible on anime
    // line art and rendered subtitles. Force smooth image filtering and keep
    // the destination rectangle pixel-aligned to avoid additional shimmer.
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);

    const QSize sourceSize(m_frame.width(), m_frame.height());
    const QSize availableSize(
        qMax(1, qRound(width())),
        qMax(1, qRound(height())));
    const QSize targetSize = sourceSize.scaled(availableSize, Qt::KeepAspectRatio);

    const qreal targetX = qRound((width() - targetSize.width()) / 2.0);
    const qreal targetY = qRound((height() - targetSize.height()) / 2.0);
    const QRectF target(
        targetX,
        targetY,
        targetSize.width(),
        targetSize.height());

    painter->drawImage(target, m_frame, QRectF(m_frame.rect()));

    if (m_testControlsVisible)
    {
        // Clickable Phase 1.2 test control bar.
        const QRectF bar = controlBarRect();
        painter->setPen(Qt::NoPen);
        painter->setBrush(QColor(0, 0, 0, 185));
        painter->drawRoundedRect(bar, 12.0, 12.0);

        const QRectF progress = progressRect();
        painter->setBrush(QColor(255, 255, 255, 70));
        painter->drawRoundedRect(progress, 4.0, 4.0);

        const qint64 length = durationMs();
        const qint64 current = positionMs();
        if (length > 0)
        {
            const qreal ratio = qBound<qreal>(0.0, static_cast<qreal>(current) / static_cast<qreal>(length), 1.0);
            QRectF played = progress;
            played.setWidth(progress.width() * ratio);
            painter->setBrush(QColor(255, 184, 74, 230));
            painter->drawRoundedRect(played, 4.0, 4.0);
        }

        auto drawButton = [painter](const QRectF& rect, const QString& label, bool active = false) {
            painter->setPen(Qt::NoPen);
            painter->setBrush(active ? QColor(255, 184, 74, 220) : QColor(255, 255, 255, 32));
            painter->drawRoundedRect(rect, 8.0, 8.0);
            painter->setPen(active ? Qt::black : Qt::white);
            QFont font = painter->font();
            font.setBold(true);
            painter->setFont(font);
            painter->drawText(rect, Qt::AlignCenter, label);
        };

        const libvlc_state_t state = m_mediaPlayer
            ? libvlc_media_player_get_state(m_mediaPlayer)
            : libvlc_NothingSpecial;

        drawButton(
            playButtonRect(),
            state == libvlc_Paused ? QStringLiteral("PLAY") : QStringLiteral("PAUSE"),
            state == libvlc_Paused);

        drawButton(backButtonRect(), QStringLiteral("-10s"));
        drawButton(forwardButtonRect(), QStringLiteral("+10s"));
        drawButton(muteButtonRect(), muted() ? QStringLiteral("UNMUTE") : QStringLiteral("MUTE"), muted());
        drawButton(volumeDownButtonRect(), QStringLiteral("-"));
        drawButton(volumeUpButtonRect(), QStringLiteral("+"));

        painter->setPen(Qt::white);
        QFont infoFont = painter->font();
        infoFont.setBold(false);
        painter->setFont(infoFont);

        const QRectF infoRect(
            forwardButtonRect().right() + 18.0,
            playButtonRect().top(),
            qMax<qreal>(0.0, muteButtonRect().left() - forwardButtonRect().right() - 36.0),
            40.0);

        painter->drawText(
            infoRect,
            Qt::AlignLeft | Qt::AlignVCenter,
            controlOverlayText());

    }

    if (!m_receivedFrame.load(std::memory_order_relaxed))
    {
        painter->drawText(
            boundingRect().adjusted(24, 24, -24, -24),
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

void VlcVideoItem::mousePressEvent(QMouseEvent* event)
{
    if (!m_mediaPlayer || event->button() != Qt::LeftButton)
    {
        QQuickPaintedItem::mousePressEvent(event);
        return;
    }

    const QPointF pos = event->position();

    if (playButtonRect().contains(pos))
    {
        togglePause();
    }
    else if (backButtonRect().contains(pos))
    {
        seekRelative(-10000);
    }
    else if (forwardButtonRect().contains(pos))
    {
        seekRelative(10000);
    }
    else if (muteButtonRect().contains(pos))
    {
        setMuted(!muted());
    }
    else if (volumeDownButtonRect().contains(pos))
    {
        setVolume(volume() - 5);
    }
    else if (volumeUpButtonRect().contains(pos))
    {
        setVolume(volume() + 5);
    }
    else if (progressRect().contains(pos))
    {
        const QRectF progress = progressRect();
        const qreal ratio = qBound<qreal>(
            0.0,
            (pos.x() - progress.left()) / qMax<qreal>(1.0, progress.width()),
            1.0);

        const qint64 length = durationMs();
        if (length > 0)
            seekTo(static_cast<qint64>(static_cast<qreal>(length) * ratio));
    }
    else
    {
        QQuickPaintedItem::mousePressEvent(event);
        return;
    }

    forceActiveFocus();
    event->accept();
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
