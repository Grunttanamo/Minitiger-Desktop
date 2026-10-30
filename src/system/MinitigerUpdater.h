#ifndef MINITIGERUPDATER_H
#define MINITIGERUPDATER_H

#include <QJsonObject>
#include <QString>

// Detached private updater (resources/updater/minitiger-updater.ps1) with its
// progress window. Windows only; the functions are no-ops elsewhere.
namespace MinitigerUpdater
{
  // Starts the updater for a verified package. params carries url,
  // expectedHash, packageType, packagePath, stagePath, appDir, appExe,
  // targetPid, targetBuild and targetVersion; the lock, log and failure
  // paths are added here. With demo the window only plays its animation.
  bool start(QJsonObject params, bool demo = false);

  // True while an updater recorded in minitiger-update.lock is running, so a
  // new Minitiger instance must not start and interfere with it.
  bool isRunning();

  // The build the web client should stop retrying, or 0. A build is only
  // given up after several failed attempts, not after the first one.
  int failedBuild();
}

#endif // MINITIGERUPDATER_H
