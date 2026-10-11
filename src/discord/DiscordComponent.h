#ifndef __DISCORD_COMPONENT_H__
#define __DISCORD_COMPONENT_H__

#include <QJsonObject>
#include <QLocalSocket>
#include <QTimer>
#include <QVariantMap>

#include "ComponentManager.h"

class DiscordComponent : public ComponentBase
{
  Q_OBJECT
  DEFINE_SINGLETON(DiscordComponent);

public:
  bool componentInitialize() override;
  const char* componentName() override { return "discord"; }
  bool componentExport() override { return true; }
  void componentPostInitialize() override;

  Q_INVOKABLE void configure(
      bool enabled,
      const QString& clientId,
      bool showTitle,
      bool showEpisode,
      bool showProgress);

  Q_INVOKABLE bool isConnected() const;
  Q_INVOKABLE void refreshPresence();
  Q_INVOKABLE void updatePlaybackActivity(
      const QVariantMap& metadata,
      qint64 positionMs,
      qint64 durationMs,
      const QString& state);
  Q_INVOKABLE void updateReadingActivity(
      const QVariantMap& metadata,
      double progress,
      const QString& state);
  Q_INVOKABLE void setArtworkUrl(const QString& url);

private:
  explicit DiscordComponent(QObject* parent = nullptr);

  void connectDiscord();
  void tryNextEndpoint();
  void sendHandshake();
  void sendActivity();
  void sendBrowsingActivity();
  void clearActivity();
  void writeFrame(qint32 opcode, const QJsonObject& payload);
  void schedulePresenceUpdate();
  void handlePositionUpdate(qint64 positionMs);
  QStringList endpointCandidates() const;
  QString formattedProgress() const;

  QLocalSocket* m_socket = nullptr;
  QTimer m_presenceTimer;
  QStringList m_endpoints;
  int m_endpointIndex = 0;

  bool m_enabled = false;
  bool m_showTitle = true;
  bool m_showEpisode = true;
  bool m_showProgress = true;
  bool m_playing = false;
  bool m_paused = false;

  QString m_clientId;
  QString m_artworkUrl;
  QString m_activityKind = "watching";
  QVariantMap m_metadata;
  double m_readingProgress = 0.0;
  qint64 m_positionMs = 0;
  qint64 m_durationMs = 0;
  qint64 m_lastProgressPresenceAtMs = 0;
  quint64 m_nonce = 0;
};

#endif
