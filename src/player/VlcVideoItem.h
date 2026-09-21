#ifndef VLCVIDEOITEM_H
#define VLCVIDEOITEM_H

#include <QImage>
#include <QMutex>
#include <QQuickPaintedItem>
#include <QRectF>
#include <QString>
#include <QTimer>
#include <atomic>

#include <vlc/vlc.h>

class QKeyEvent;
class QMouseEvent;
class QPainter;

class VlcVideoItem : public QQuickPaintedItem
{
    Q_OBJECT

public:
    explicit VlcVideoItem(QQuickItem* parent = nullptr);
    ~VlcVideoItem() override;

    void paint(QPainter* painter) override;

    Q_INVOKABLE bool playSource(const QString& source, qint64 startMilliseconds = 0, bool autoplay = true, const QString& userAgent = QString());
    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void pausePlayback();
    Q_INVOKABLE void resumePlayback();
    Q_INVOKABLE void stopPlayback();

    Q_INVOKABLE void seekTo(qint64 positionMs);
    Q_INVOKABLE void seekRelative(qint64 deltaMs);
    Q_INVOKABLE qint64 positionMs() const;
    Q_INVOKABLE qint64 durationMs() const;

    Q_INVOKABLE void setVolume(int volume);
    Q_INVOKABLE int volume() const;
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE bool muted() const;
    Q_INVOKABLE void setPlaybackRate(double rate);
    Q_INVOKABLE void setTestControlsVisible(bool visible) { m_testControlsVisible = visible; update(); }

    QString lastError() const { return m_lastError; }

Q_SIGNALS:
    void playbackStarted();
    void playbackPaused();
    void playbackFinished();
    void playbackError(const QString& message);
    void positionChanged(qint64 milliseconds);
    void durationChanged(qint64 milliseconds);

protected:
    void keyPressEvent(QKeyEvent* event) override;
    void mousePressEvent(QMouseEvent* event) override;

private:
    static void* lockVideo(void* opaque, void** planes);
    static void unlockVideo(void* opaque, void* picture, void* const* planes);
    static void displayVideo(void* opaque, void* picture);
    static unsigned setupVideoFormat(void** opaque,
                                     char* chroma,
                                     unsigned* width,
                                     unsigned* height,
                                     unsigned* pitches,
                                     unsigned* lines);
    static void cleanupVideoFormat(void* opaque);

    bool ensureVlc();
    void releasePlayer();
    void setError(const QString& error);
    QString controlOverlayText() const;
    void pollPlaybackState();

    QRectF controlBarRect() const;
    QRectF progressRect() const;
    QRectF playButtonRect() const;
    QRectF backButtonRect() const;
    QRectF forwardButtonRect() const;
    QRectF muteButtonRect() const;
    QRectF volumeDownButtonRect() const;
    QRectF volumeUpButtonRect() const;

    libvlc_instance_t* m_vlc = nullptr;
    libvlc_media_player_t* m_mediaPlayer = nullptr;

    QImage m_frame;
    QMutex m_frameMutex;
    QString m_lastError;
    QString m_status = QStringLiteral("VLC surface ready - waiting for media");
    std::atomic_bool m_receivedFrame { false };
    unsigned m_videoWidth = 0;
    unsigned m_videoHeight = 0;
    int m_volume = 40;
    QTimer m_pollTimer;
    libvlc_state_t m_lastPolledState = libvlc_NothingSpecial;
    qint64 m_lastDurationMs = -1;
    qint64 m_pendingStartMs = 0;
    bool m_pendingAutoplay = true;
    bool m_pendingInitialSeek = false;
    bool m_testControlsVisible = true;
};

#endif // VLCVIDEOITEM_H
