#pragma once
#include <MpvAbstractItem>
#include <QString>

// Standalone MPV surface. This class must never share the normal PlayerComponent.
class MinitigerPreviewVideoItem : public MpvAbstractItem
{
    Q_OBJECT
    Q_PROPERTY(bool readyForPreview READ readyForPreview NOTIFY readyForPreviewChanged)
public:
    explicit MinitigerPreviewVideoItem(QQuickItem* parent = nullptr);
    bool readyForPreview() const { return m_ready; }
    Q_INVOKABLE void primeRender() { update(); }
    Q_INVOKABLE bool playPreview(const QString& url, bool loop);
    Q_INVOKABLE bool previewEnded() const;
    Q_INVOKABLE QString previewStatus() const;
    Q_INVOKABLE void stopPreview();
    Q_INVOKABLE void setPreviewMuted(bool muted);
signals:
    void readyForPreviewChanged();
private:
    bool m_ready = false;
};
