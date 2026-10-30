#include "MinitigerUpdater.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QProcess>
#include <QStandardPaths>
#include <QStringList>

#include "Paths.h"

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace
{
// Keep in sync with $maxAttempts in minitiger-updater.ps1.
constexpr int kMaxAttempts = 3;
// A lock older than this is stale (crashed updater, reused PID).
constexpr qint64 kLockMaxAgeSecs = 45 * 60;

QString lockPath() { return Paths::globalDataDir("minitiger-update.lock"); }
QString failureMarkerPath() { return Paths::globalDataDir("minitiger-update-failed-build.txt"); }
QString logPath() { return Paths::globalDataDir("minitiger-update.log"); }

bool copyResource(const QString& resource, const QString& target)
{
  QFile::remove(target);
  if (!QFile::copy(resource, target))
    return false;
  // Files copied from Qt resources are read-only; the next update must be
  // able to replace them.
  QFile::setPermissions(target, QFile::ReadOwner | QFile::WriteOwner);
  return true;
}
}

/////////////////////////////////////////////////////////////////////////////////////////
bool MinitigerUpdater::start(QJsonObject params, bool demo)
{
#ifdef Q_OS_WIN
  const QString root =
    QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation)).filePath("MinitigerDesktopUpdate");
  if (!QDir().mkpath(root))
  {
    qWarning() << "Could not create Minitiger update temp directory:" << root;
    return false;
  }

  const QString scriptPath = QDir(root).filePath("minitiger-updater.ps1");
  if (!copyResource(":/updater/minitiger-updater.ps1", scriptPath))
  {
    qWarning() << "Could not write Minitiger updater script:" << scriptPath;
    return false;
  }
  // Optional: the window falls back to the executable's icon.
  copyResource(":/images/icon.png", QDir(root).filePath("minitiger-updater-logo.png"));

  params.insert("lockPath", QDir::toNativeSeparators(lockPath()));
  params.insert("logPath", QDir::toNativeSeparators(logPath()));
  params.insert("failureMarker", QDir::toNativeSeparators(failureMarkerPath()));
  params.insert("demo", demo);
  if (!params.contains("appExe"))
    params.insert("appExe", QDir::toNativeSeparators(QDir(QCoreApplication::applicationDirPath()).filePath("Minitiger Desktop.exe")));

  const QString paramsPath =
    QDir(root).filePath(QString("update-params-%1.json").arg(QCoreApplication::applicationPid()));
  QFile paramsFile(paramsPath);
  if (!paramsFile.open(QIODevice::WriteOnly | QIODevice::Truncate))
  {
    qWarning() << "Could not write Minitiger updater parameters:" << paramsPath;
    return false;
  }
  paramsFile.write(QJsonDocument(params).toJson(QJsonDocument::Indented));
  paramsFile.close();

  // Windows PowerShell 5.1 ships with every Windows. -STA is required for
  // the WinForms window; -WindowStyle Hidden hides only the console.
  const QStringList arguments = {
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-WindowStyle", "Hidden",
    "-File", QDir::toNativeSeparators(scriptPath),
    "-ParamsFile", QDir::toNativeSeparators(paramsPath)
  };
  if (!QProcess::startDetached("powershell.exe", arguments))
  {
    qWarning() << "Could not start the Minitiger updater.";
    return false;
  }
  return true;
#else
  Q_UNUSED(params);
  Q_UNUSED(demo);
  return false;
#endif
}

/////////////////////////////////////////////////////////////////////////////////////////
bool MinitigerUpdater::isRunning()
{
#ifdef Q_OS_WIN
  QFile lock(lockPath());
  if (!lock.open(QIODevice::ReadOnly))
    return false;
  const QStringList lines = QString::fromLatin1(lock.readAll()).split('\n', Qt::SkipEmptyParts);
  lock.close();

  if (QFileInfo(lock).lastModified().secsTo(QDateTime::currentDateTime()) > kLockMaxAgeSecs)
    return false;

  bool ok = false;
  const DWORD pid = lines.value(0).trimmed().toULong(&ok);
  if (!ok || pid == 0)
    return false;

  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process)
    return false;
  DWORD exitCode = 0;
  const bool running = GetExitCodeProcess(process, &exitCode) && exitCode == STILL_ACTIVE;
  CloseHandle(process);
  return running;
#else
  return false;
#endif
}

/////////////////////////////////////////////////////////////////////////////////////////
int MinitigerUpdater::failedBuild()
{
  QFile marker(failureMarkerPath());
  if (!marker.open(QIODevice::ReadOnly | QIODevice::Text))
    return 0;

  // "build attempts"; older updaters wrote just the build (one attempt).
  const QStringList parts =
    QString::fromUtf8(marker.readAll()).simplified().split(' ', Qt::SkipEmptyParts);
  bool buildOk = false;
  const int build = parts.value(0).toInt(&buildOk);
  bool attemptsOk = false;
  int attempts = parts.value(1).toInt(&attemptsOk);
  if (!attemptsOk)
    attempts = 1;

  return buildOk && build > 0 && attempts >= kMaxAttempts ? build : 0;
}
