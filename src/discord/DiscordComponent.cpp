#include "DiscordComponent.h"

#include <QCoreApplication>
#include <QDataStream>
#include <QDateTime>
#include <QDir>
#include <QJsonDocument>
#include <QJsonValue>
#include <QProcessEnvironment>
#include <QtGlobal>

#include "player/PlayerComponent.h"

DiscordComponent::DiscordComponent(QObject* parent)
  : ComponentBase(parent)
{
  m_presenceTimer.setSingleShot(true);
  m_presenceTimer.setInterval(220);

  // A single reconnect timer. Every presence update used to start its own
  // retry chain while Discord was not running, so chains piled up for the
  // whole playback session.
  m_reconnectTimer.setSingleShot(true);
  connect(&m_reconnectTimer, &QTimer::timeout, this, [this]() {
    connectDiscord();
  });

  connect(&m_presenceTimer, &QTimer::timeout, this, [this]() {
    if (!m_enabled || m_clientId.trimmed().isEmpty())
      return;

    if (!m_socket || m_socket->state() != QLocalSocket::ConnectedState)
    {
      // A pending reconnect sends the activity once connected.
      if (!m_reconnectTimer.isActive())
        connectDiscord();
      return;
    }

    sendActivity();
  });
}

bool DiscordComponent::componentInitialize()
{
  m_socket = new QLocalSocket(this);

  connect(m_socket, &QLocalSocket::connected, this, [this]() {
    sendHandshake();
    QTimer::singleShot(180, this, [this]() {
      sendActivity();
    });
  });

  connect(m_socket, &QLocalSocket::readyRead, this, [this]() {
    // Discord replies to every RPC command. We do not need the response
    // payload for presence updates, but it must be drained so the local
    // socket buffer cannot fill during long playback sessions.
    m_socket->readAll();
  });

  connect(m_socket, &QLocalSocket::disconnected, this, [this]() {
    if (m_enabled)
      scheduleReconnect(1500);
  });

  connect(
      m_socket,
      &QLocalSocket::errorOccurred,
      this,
      [this](QLocalSocket::LocalSocketError) {
        if (!m_enabled)
          return;

        // Qt emits errorOccurred before the socket returns to
        // UnconnectedState (at least on Unix), so a direct call would stop
        // the endpoint walk after discord-ipc-0. Continue once the state
        // has settled.
        QMetaObject::invokeMethod(this, [this]() {
          tryNextEndpoint();
        }, Qt::QueuedConnection);
      });

  return true;
}

void DiscordComponent::componentPostInitialize()
{
  auto& player = PlayerComponent::Get();

  connect(&player, &PlayerComponent::onMetaData, this,
          [this](const QVariantMap& metadata, const QUrl&) {
    m_metadata = metadata;
    m_positionMs = 0;
    m_durationMs = metadata.value("RunTimeTicks").toLongLong() / 10000;
    schedulePresenceUpdate();
  });

  // Jellyfin-web also forwards canonical media-session metadata through
  // notifyMetadata()/metadataChanged(). Native queue metadata is not emitted
  // on every playback path, so Rich Presence must listen to both.
  connect(&player, &PlayerComponent::metadataChanged, this,
          [this](const QVariantMap& metadata) {
    if (!metadata.isEmpty())
      m_metadata = metadata;

    const qint64 ticks = metadata.value("RunTimeTicks").toLongLong();
    if (ticks > 0)
      m_durationMs = ticks / 10000;

    schedulePresenceUpdate();
  });

  connect(&player, &PlayerComponent::positionUpdate, this,
          [this](quint64 positionMs) {
    handlePositionUpdate(static_cast<qint64>(positionMs));
  });

  connect(&player, &PlayerComponent::positionChanged, this,
          [this](qint64 positionMs) {
    handlePositionUpdate(positionMs);
  });

  connect(&player, &PlayerComponent::updateDuration, this,
          [this](qint64 durationMs) {
    m_durationMs = qMax<qint64>(0, durationMs);
    schedulePresenceUpdate();
  });

  connect(&player, &PlayerComponent::durationChanged, this,
          [this](qint64 durationMs) {
    m_durationMs = qMax<qint64>(0, durationMs);
    schedulePresenceUpdate();
  });

  connect(&player, &PlayerComponent::playing, this, [this]() {
    m_playing = true;
    m_paused = false;
    schedulePresenceUpdate();
  });

  connect(&player, &PlayerComponent::paused, this, [this]() {
    m_playing = true;
    m_paused = true;
    schedulePresenceUpdate();
  });

  const auto clearPlayback = [this]() {
    m_playing = false;
    m_paused = false;
    m_metadata.clear();
    m_artworkUrl.clear();
    m_activityKind = "watching";
    m_readingProgress = 0.0;
    m_positionMs = 0;
    m_durationMs = 0;
    schedulePresenceUpdate();
  };

  connect(&player, &PlayerComponent::finished, this, clearPlayback);
  connect(&player, &PlayerComponent::canceled, this, clearPlayback);
  connect(&player, &PlayerComponent::stopped, this, clearPlayback);
  connect(&player, &PlayerComponent::error, this,
          [clearPlayback](const QString&) {
    clearPlayback();
  });
}

void DiscordComponent::configure(
    bool enabled,
    const QString& clientId,
    bool showTitle,
    bool showEpisode,
    bool showProgress)
{
  const QString normalizedClientId = clientId.trimmed();
  const bool reconnect =
      normalizedClientId != m_clientId
      || enabled != m_enabled;

  m_enabled = enabled;
  m_clientId = normalizedClientId;
  m_showTitle = showTitle;
  m_showEpisode = showEpisode;
  m_showProgress = showProgress;

  if (!m_enabled || m_clientId.isEmpty())
  {
    m_reconnectTimer.stop();

    if (m_socket && m_socket->state() == QLocalSocket::ConnectedState)
      clearActivity();

    if (m_socket)
      m_socket->abort();

    return;
  }

  if (reconnect && m_socket)
    m_socket->abort();

  connectDiscord();
}

bool DiscordComponent::isConnected() const
{
  return m_socket
      && m_socket->state() == QLocalSocket::ConnectedState;
}

void DiscordComponent::refreshPresence()
{
  schedulePresenceUpdate();
}

void DiscordComponent::updatePlaybackActivity(
    const QVariantMap& metadata,
    qint64 positionMs,
    qint64 durationMs,
    const QString& state)
{
  m_activityKind = "watching";
  m_readingProgress = 0.0;
  if (!metadata.isEmpty())
    m_metadata = metadata;

  m_positionMs = qMax<qint64>(0, positionMs);

  if (durationMs > 0)
    m_durationMs = durationMs;

  if (state.compare("Playing", Qt::CaseInsensitive) == 0)
  {
    m_playing = true;
    m_paused = false;
  }
  else if (state.compare("Paused", Qt::CaseInsensitive) == 0)
  {
    m_playing = true;
    m_paused = true;
  }
  else if (state.compare("Stopped", Qt::CaseInsensitive) == 0)
  {
    m_playing = false;
    m_paused = false;
    m_metadata.clear();
    m_artworkUrl.clear();
    m_positionMs = 0;
    m_durationMs = 0;
  }

  schedulePresenceUpdate();
}

void DiscordComponent::updateReadingActivity(
    const QVariantMap& metadata,
    double progress,
    const QString& state)
{
  if (state.compare("Stopped", Qt::CaseInsensitive) == 0)
  {
    m_playing = false;
    m_paused = false;
    m_metadata.clear();
    m_artworkUrl.clear();
    m_activityKind = "watching";
    m_readingProgress = 0.0;
    m_positionMs = 0;
    m_durationMs = 0;
    schedulePresenceUpdate();
    return;
  }

  if (!metadata.isEmpty())
    m_metadata = metadata;

  // Do not retain the previous video/movie artwork when switching to a
  // book reader. Reading artwork can be added independently later.
  m_artworkUrl.clear();
  m_activityKind = "reading";
  m_readingProgress = qBound(0.0, progress, 1.0);
  m_playing = true;
  m_paused = false;
  m_positionMs = 0;
  m_durationMs = 0;
  schedulePresenceUpdate();
}

void DiscordComponent::setArtworkUrl(const QString& url)
{
  const QString trimmed = url.trimmed();

  if (trimmed.size() > 300)
    return;

  if (!trimmed.isEmpty()
      && !trimmed.startsWith("https://", Qt::CaseInsensitive))
    return;

  m_artworkUrl = trimmed;
  schedulePresenceUpdate();
}

QStringList DiscordComponent::endpointCandidates() const
{
  QStringList result;

#ifdef Q_OS_WIN
  for (int index = 0; index < 10; ++index)
    result << QString("discord-ipc-%1").arg(index);
#else
  const auto env = QProcessEnvironment::systemEnvironment();
  const QStringList roots = {
    env.value("XDG_RUNTIME_DIR"),
    env.value("TMPDIR"),
    QStringLiteral("/tmp")
  };

  for (const QString& root : roots)
  {
    if (root.isEmpty())
      continue;

    for (int index = 0; index < 10; ++index)
      result << QDir(root).filePath(QString("discord-ipc-%1").arg(index));
  }

  for (int index = 0; index < 10; ++index)
    result << QString("discord-ipc-%1").arg(index);
#endif

  result.removeDuplicates();
  return result;
}

void DiscordComponent::connectDiscord()
{
  if (!m_enabled || m_clientId.isEmpty() || !m_socket)
    return;

  if (m_socket->state() == QLocalSocket::ConnectedState
      || m_socket->state() == QLocalSocket::ConnectingState)
    return;

  m_reconnectTimer.stop();
  m_endpoints = endpointCandidates();
  m_endpointIndex = 0;
  tryNextEndpoint();
}

void DiscordComponent::tryNextEndpoint()
{
  if (!m_enabled || !m_socket)
    return;

  if (m_socket->state() != QLocalSocket::UnconnectedState)
    return;

  if (m_endpointIndex >= m_endpoints.size())
  {
    scheduleReconnect(3500);
    return;
  }

  const QString endpoint = m_endpoints.at(m_endpointIndex++);
  m_socket->connectToServer(endpoint, QIODevice::ReadWrite);
}

void DiscordComponent::scheduleReconnect(int delayMs)
{
  if (!m_enabled || m_reconnectTimer.isActive())
    return;

  m_reconnectTimer.start(delayMs);
}

void DiscordComponent::sendHandshake()
{
  QJsonObject payload;
  payload.insert("v", 1);
  payload.insert("client_id", m_clientId);
  writeFrame(0, payload);
}

QString DiscordComponent::formattedProgress() const
{
  auto formatMs = [](qint64 milliseconds) {
    const qint64 totalSeconds = qMax<qint64>(0, milliseconds) / 1000;
    const qint64 hours = totalSeconds / 3600;
    const qint64 minutes = (totalSeconds % 3600) / 60;
    const qint64 seconds = totalSeconds % 60;

    if (hours > 0)
      return QString("%1:%2:%3")
          .arg(hours)
          .arg(minutes, 2, 10, QLatin1Char('0'))
          .arg(seconds, 2, 10, QLatin1Char('0'));

    return QString("%1:%2")
        .arg(minutes)
        .arg(seconds, 2, 10, QLatin1Char('0'));
  };

  return QString("%1 / %2")
      .arg(formatMs(m_positionMs))
      .arg(formatMs(m_durationMs));
}

void DiscordComponent::sendBrowsingActivity()
{
  QJsonObject activity;
  activity.insert("type", 3);
  activity.insert("details", "Durchstöbert Minitiger");
  activity.insert("status_display_type", 2);

  QJsonObject assets;
  assets.insert("large_image", "minitiger");
  assets.insert("large_text", "Minitiger Desktop");
  activity.insert("assets", assets);

  QJsonObject args;
  args.insert("pid", static_cast<qint64>(QCoreApplication::applicationPid()));
  args.insert("activity", activity);

  QJsonObject payload;
  payload.insert("cmd", "SET_ACTIVITY");
  payload.insert("args", args);
  payload.insert("nonce", QString::number(++m_nonce));

  writeFrame(1, payload);
}

void DiscordComponent::sendActivity()
{
  if (!m_enabled || m_clientId.isEmpty())
    return;

  if (!m_playing || m_metadata.isEmpty())
  {
    sendBrowsingActivity();
    return;
  }

  const QString type = m_metadata.value("Type").toString();
  const QString name = m_metadata.value("Name").toString();
  const QString seriesName = m_metadata.value("SeriesName").toString();
  const int seasonNumber = m_metadata.value("ParentIndexNumber").toInt();
  const int episodeNumber = m_metadata.value("IndexNumber").toInt();

  QString title = seriesName;
  if (title.isEmpty())
    title = name;

  QJsonObject activity;
  activity.insert("type", 3);

  const bool isReading =
      m_activityKind.compare("reading", Qt::CaseInsensitive) == 0;

  if (isReading)
  {
    if (m_showTitle && !title.isEmpty())
      activity.insert("details", QString("Liest %1").arg(title));
    else
      activity.insert("details", "Liest in Minitiger");

    // Newer Discord clients can use the details field for the compact
    // profile status text. Older clients simply ignore this field.
    activity.insert("status_display_type", 2);
  }
  else if (m_showTitle && !title.isEmpty())
  {
    activity.insert("details", QString("Schaut %1").arg(title));
    activity.insert("status_display_type", 2);
  }
  else
  {
    activity.insert("details", "Schaut gerade Minitiger");
    activity.insert("status_display_type", 2);
  }

  QStringList stateParts;

  if (!isReading && m_paused)
    stateParts << "Pausiert";

  if (!isReading
      && m_showEpisode
      && type.compare("Episode", Qt::CaseInsensitive) == 0)
  {
    if (seasonNumber > 0)
      stateParts << QString("Staffel %1").arg(seasonNumber);

    if (episodeNumber > 0)
      stateParts << QString("Folge %1").arg(episodeNumber);

    if (!name.isEmpty())
      stateParts << name;
  }

  if (isReading && m_readingProgress > 0.0)
  {
    stateParts << QString("%1 % gelesen")
        .arg(qRound(m_readingProgress * 100.0));
  }
  else if (m_showProgress && m_durationMs > 0 && m_paused)
  {
    stateParts << formattedProgress();
  }

  if (!stateParts.isEmpty())
    activity.insert("state", stateParts.join(" · "));

  if (!isReading
      && m_showProgress
      && !m_paused
      && m_durationMs > 0
      && m_positionMs >= 0
      && m_positionMs < m_durationMs)
  {
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    QJsonObject timestamps;
    timestamps.insert("start", now - (m_positionMs / 1000));
    timestamps.insert("end", now + ((m_durationMs - m_positionMs) / 1000));
    activity.insert("timestamps", timestamps);
  }

  QJsonObject assets;
  assets.insert(
      "large_image",
      m_artworkUrl.isEmpty()
          ? QString("minitiger")
          : m_artworkUrl);
  assets.insert(
      "large_text",
      title.isEmpty()
          ? QString("Minitiger Desktop")
          : title);
  activity.insert("assets", assets);

  QJsonObject args;
  args.insert("pid", static_cast<qint64>(QCoreApplication::applicationPid()));
  args.insert("activity", activity);

  QJsonObject payload;
  payload.insert("cmd", "SET_ACTIVITY");
  payload.insert("args", args);
  payload.insert("nonce", QString::number(++m_nonce));

  writeFrame(1, payload);
}

void DiscordComponent::clearActivity()
{
  if (!m_socket || m_socket->state() != QLocalSocket::ConnectedState)
    return;

  QJsonObject args;
  args.insert("pid", static_cast<qint64>(QCoreApplication::applicationPid()));
  args.insert("activity", QJsonValue::Null);

  QJsonObject payload;
  payload.insert("cmd", "SET_ACTIVITY");
  payload.insert("args", args);
  payload.insert("nonce", QString::number(++m_nonce));

  writeFrame(1, payload);
}

void DiscordComponent::writeFrame(qint32 opcode, const QJsonObject& payload)
{
  if (!m_socket || m_socket->state() != QLocalSocket::ConnectedState)
    return;

  const QByteArray body =
      QJsonDocument(payload).toJson(QJsonDocument::Compact);

  QByteArray frame;
  QDataStream stream(&frame, QIODevice::WriteOnly);
  stream.setByteOrder(QDataStream::LittleEndian);
  stream << opcode;
  stream << static_cast<qint32>(body.size());
  frame.append(body);

  m_socket->write(frame);
  m_socket->flush();
}

void DiscordComponent::handlePositionUpdate(qint64 positionMs)
{
  const qint64 normalizedPosition = qMax<qint64>(0, positionMs);
  const qint64 previousPosition = m_positionMs;
  m_positionMs = normalizedPosition;

  if (!m_showProgress || !m_playing || m_paused)
    return;

  // Discord computes the moving progress bar from timestamps. Native mpv
  // reports position many times per second, but repeatedly scheduling a
  // presence update for each tick can starve a trailing-edge debounce.
  // Refresh infrequently during ordinary playback and promptly for seeks.
  const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
  const bool seeked = qAbs(normalizedPosition - previousPosition) > 5000;
  if (seeked || m_lastProgressPresenceAtMs == 0
      || nowMs - m_lastProgressPresenceAtMs >= 15000)
  {
    m_lastProgressPresenceAtMs = nowMs;
    schedulePresenceUpdate();
  }
}

void DiscordComponent::schedulePresenceUpdate()
{
  if (!m_enabled || m_clientId.isEmpty())
    return;

  // Coalesce events without postponing the deadline on each new signal.
  // In particular, positionUpdate must never keep the Discord activity
  // indefinitely stuck in "Durchstöbert Minitiger" while video is playing.
  if (!m_presenceTimer.isActive())
    m_presenceTimer.start();
}
