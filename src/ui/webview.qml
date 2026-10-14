import QtQuick
import Konvergo 1.0
import QtWebEngine
import QtWebChannel
import QtQuick.Window
import QtQuick.Controls
import Qt.labs.platform as Labs

Window
{
  id: mainWindow
  title: "Minitiger Desktop"
  objectName: "mainWindow"
  width: 1280
  height: 720
  minimumWidth: 213
  minimumHeight: 120
  visible: true
  color: "#000000"

  // Properties previously from KonvergoWindow
  property bool webDesktopMode: true
  property bool showDebugLayer: false
  property string debugInfo: ""
  property string videoInfo: ""
  property string webUrl: ""

  property bool showSystemTrayIcon: webDesktopMode && components.system.isWindows &&
                                    components.settings.windowsTrayIcon

  signal reloadWebClient()
  property bool videoActiveForPopout: false
  property bool videoPoppedOut: false
  property bool videoPopoutPaused: false
  property bool popoutControlsVisible: true
  property bool popoutButtonVisible: true
  property bool popoutTransitioning: false
  property bool popoutBrowseEnabled: false
  property rect savedMainGeometry: Qt.rect(0, 0, 1280, 720)
  property int savedMainVisibility: Window.Windowed
  property bool popoutBrowserLoaded: false
  property bool restoringMainWindow: false

  // Do not write temporary 960x540 pop-out dimensions to persistent settings.
  Timer {
    id: finishWindowRestore
    interval: 1100
    repeat: false
    onTriggered: mainWindow.restoringMainWindow = false
  }

  Timer {
    id: restoreNativeWindowMode
    interval: 150
    repeat: false
    onTriggered: {
      if (!mainWindow.restoringMainWindow)
        return;
      if (mainWindow.savedMainVisibility === Window.Maximized)
        mainWindow.showMaximized();
      else if (mainWindow.savedMainVisibility === Window.FullScreen)
        mainWindow.showFullScreen();
      else
        mainWindow.showNormal();
      mainWindow.raise();
      mainWindow.requestActivate();
      components.window.setCursorVisibility(true);
    }
  }

  // MPV stays in the original scene graph for its entire lifetime. Moving an
  // MpvAbstractItem between QQuickWindows invalidates its render targets,
  // producing blue frames, broken ASS subtitles and eventual GPU crashes.
  // Instead we turn the EXISTING window into the detachable video surface.
  function setVideoPopout(enable) {
    if (enable === videoPoppedOut || popoutTransitioning)
      return;
    if (enable && !videoActiveForPopout)
      return;

    popoutTransitioning = true;
    if (enable) {
      savedMainVisibility = mainWindow.visibility;
      savedMainGeometry = Qt.rect(mainWindow.x, mainWindow.y, mainWindow.width, mainWindow.height);
      browseWindow.x = savedMainGeometry.x;
      browseWindow.y = savedMainGeometry.y;
      browseWindow.width = savedMainGeometry.width;
      browseWindow.height = savedMainGeometry.height;
      videoPoppedOut = true;
      // Keep the original video/OSD scene and its renderer untouched.
      // The browsing window must retain the previous size/placement.
      if (savedMainVisibility === Window.Maximized)
        browseWindow.showMaximized();
      else if (savedMainVisibility === Window.FullScreen)
        browseWindow.showFullScreen();
      else
        browseWindow.show();
      if (!popoutBrowserLoaded) {
        popoutBrowserLoaded = true;
        var current = web.url.toString();
        var base = current.split("#")[0];
        browseWeb.url = base + "#/home";
      }
      // Preserve the original window's maximize/fullscreen state separately.
      mainWindow.showNormal();
      mainWindow.width = 960;
      mainWindow.height = 540;
      mainWindow.x = savedMainGeometry.x + 60;
      mainWindow.y = savedMainGeometry.y + 60;
      mainWindow.title = "Minitiger – Video-Pop-out";
      // The video remains foreground, even when another application focuses.
      components.window.setVideoPopoutTopmost(true);
      mainWindow.raise();
      mainWindow.requestActivate();
      // The web OSD owns player controls and their auto-hide timer.
    } else {
      restoringMainWindow = true;
      videoPoppedOut = false;
      components.window.setVideoPopoutTopmost(false);
      browseWindow.hide();
      mainWindow.title = "Minitiger Desktop";
      mainWindow.showNormal();
      mainWindow.x = savedMainGeometry.x;
      mainWindow.y = savedMainGeometry.y;
      mainWindow.width = savedMainGeometry.width;
      mainWindow.height = savedMainGeometry.height;
      // Windows completes showNormal asynchronously. Restoring maximized or
      // borderless/fullscreen in the same GUI tick is often silently lost.
      restoreNativeWindowMode.restart();
      finishWindowRestore.restart();
      // Clear the original OSD's previous idle state when re-docking,
      // otherwise its invisible-cursor state can survive focus changes.
      web.runJavaScript("document.body.classList.remove('mouseIdle')");
      mainWindow.raise();
      mainWindow.requestActivate();
    }
    components.window.setCursorVisibility(true);
    popoutTransitioning = false;
  }

  Connections {
    target: components.player
    function onPlaying() {
      mainWindow.videoActiveForPopout = true;
      mainWindow.videoPopoutPaused = false;
      mainWindow.popoutButtonVisible = true;
    }
    function onPaused() { mainWindow.videoPopoutPaused = true; }
    function onPlaybackStopped(isNavigating) {
      if (!isNavigating) {
        mainWindow.videoActiveForPopout = false;
        if (mainWindow.videoPoppedOut)
          mainWindow.setVideoPopout(false);
      }
    }
  }

  Window {
    id: browseWindow
    title: "Minitiger Desktop – Mediathek"
    visible: false
    width: 1280
    height: 720
    minimumWidth: 600
    minimumHeight: 400
    color: "#101014"
    onClosing: function(close) {
      close.accepted = false;
      mainWindow.setVideoPopout(false);
    }
    onActiveChanged: {
      if (active)
        components.window.setCursorVisibility(true);
    }

    WebEngineView {
      id: browseWeb
      anchors.fill: parent
      backgroundColor: "#101014"
      profile: web.profile
      webChannel: webChannelObject
      settings.localContentCanAccessRemoteUrls: true
      settings.localContentCanAccessFileUrls: true
      settings.playbackRequiresUserGesture: false
      onLoadingChanged: function(info) {
        components.window.setCursorVisibility(true);
        if (info.status === WebEngineView.LoadSucceededStatus) {
          // The browsing view shares the native player with the video window
          // but must not navigate to the fullscreen video OSD itself.
          browseWeb.runJavaScript("window.__minitigerBrowseOnly = true");
        }
      }
    }
  }

  // Pop-out / Andocken lives in Jellyfin's existing bottom-right
  // video OSD. Never overlay the player with separate Qt buttons.

  Component.onCompleted: {
    if (components && components.settings) {
      webUrl = components.settings.getWebClientUrl(webDesktopMode)
    }
  }

  onClosing: function(close) {
    if (showSystemTrayIcon) {
      // Minimize to tray on close.
      close.accepted = false
      mainWindow.hide()
    }
  }

  function toggleFullscreen() {
    visibility = (visibility === Window.FullScreen) ? Window.Windowed : Window.FullScreen
  }

  function toggleDebug() {
    showDebugLayer = !showDebugLayer
  }

  function setFullScreen(enable) {
    visibility = enable ? Window.FullScreen : Window.Windowed
  }

  function minimizeWindow() {
    if (visibility !== Window.FullScreen)
      visibility = Window.Minimized
  }

  function restoreWindow() {
    mainWindow.show()
    mainWindow.raise()
    mainWindow.requestActivate()
  }

  function runWebAction(action)
  {
    if (mainWindow.webDesktopMode)
      web.triggerWebAction(action)
  }

  Action
  {
    enabled: mainWindow.webDesktopMode
    shortcut:
    {
      if (components.system.isMacos) return "Ctrl+Meta+F"
      return "F11"
    }
    onTriggered: mainWindow.toggleFullscreen()
  }

  Action
  {
    shortcut: "Alt+Return"
    enabled:
    {
      if (mainWindow.webDesktopMode && components.system.isWindows)
        return true;
      return false;
    }
    onTriggered: mainWindow.toggleFullscreen()
  }

  Action
  {
    enabled: mainWindow.webDesktopMode
    shortcut: StandardKey.Close
    onTriggered: mainWindow.close()
  }

  Action
  {
    enabled: mainWindow.webDesktopMode
    shortcut: {
      if (components.system.isMacos) return "Ctrl+M";
      return "Meta+Down";
    }
    onTriggered: mainWindow.minimizeWindow()
  }

  Action
  {
    enabled: mainWindow.webDesktopMode
    shortcut: components.system.isWindows ? "Ctrl+Q" : StandardKey.Quit
    onTriggered: Qt.quit()
  }

  Action
  {
    shortcut: "Ctrl+Shift+D"
    enabled: mainWindow.webDesktopMode
    onTriggered: mainWindow.toggleDebug()
  }

  Action
  {
    shortcut: StandardKey.Copy
    onTriggered: runWebAction(WebEngineView.Copy)
    id: action_copy
  }

  Action
  {
    shortcut: StandardKey.Cut
    onTriggered: runWebAction(WebEngineView.Cut)
    id: action_cut
  }

  Action
  {
    shortcut: StandardKey.Paste
    onTriggered: runWebAction(WebEngineView.Paste)
    id: action_paste
  }

  Action
  {
    shortcut: StandardKey.SelectAll
    onTriggered: runWebAction(WebEngineView.SelectAll)
    id: action_selectall
  }

  Action
  {
    shortcut: StandardKey.Undo
    onTriggered: runWebAction(WebEngineView.Undo)
    id: action_undo
  }

  Action
  {
    shortcut: StandardKey.Redo
    onTriggered: runWebAction(WebEngineView.Redo)
    id: action_redo
  }

  Action
  {
    shortcut: StandardKey.Back
    onTriggered: runWebAction(WebEngineView.Back)
    id: action_back
  }

  Action
  {
    shortcut: StandardKey.Forward
    onTriggered: runWebAction(WebEngineView.Forward)
    id: action_forward
  }

  Action
  {
    enabled: mainWindow.webDesktopMode
    shortcut: "Ctrl+0"
    onTriggered: web.zoomFactor = 1.0
  }

  WebChannel
  {
    id: webChannelObject
  }

  Binding
  {
    target: web
    property: "zoomFactor"
    value: 1.0
    when: !components.settings.allowBrowserZoom()
  }

  MpvVideoItem
  {
    id: video
    objectName: "video"
    enabled: true

    anchors.fill: mainWindow.contentItem

    Component.onCompleted: {
      console.log("MpvVideoItem size:", width, "x", height, "visible:", visible)
    }
    onWidthChanged: console.log("MpvVideoItem width changed:", width)
    onHeightChanged: console.log("MpvVideoItem height changed:", height)
  }

  // Qt WebEngine's default Qt Quick file picker can incorrectly fall back to
  // single-file selection on Windows even when the HTML input uses
  // multiple. Handle only true multi-file requests ourselves and leave all
  // other WebEngine file dialogs untouched.
  Labs.FileDialog
  {
    id: webMultipleFileDialog
    title: "Dateien auswählen"
    fileMode: Labs.FileDialog.OpenFiles
    nameFilters: [ "Alle Dateien (*)" ]

    property var webRequest: null

    function localPath(fileUrl)
    {
      var value = decodeURIComponent(fileUrl.toString());

      if (value.indexOf("file:///") === 0)
      {
        value = value.substring(7);

        // file:///C:/... becomes /C:/... after stripping the scheme.
        // Chromium expects a local Windows path, not a file URL.
        if (components.system.isWindows &&
            value.length >= 3 &&
            value.charAt(0) === "/" &&
            value.charAt(2) === ":")
          value = value.substring(1);

        return value;
      }

      if (value.indexOf("file://") === 0)
        return value.substring(7);

      return value;
    }

    onAccepted:
    {
      if (!webRequest)
        return;

      var selectedPaths = [];
      for (var i = 0; i < files.length; ++i)
        selectedPaths.push(localPath(files[i]));

      var request = webRequest;
      webRequest = null;

      if (selectedPaths.length > 0)
        request.dialogAccept(selectedPaths);
      else
        request.dialogReject();
    }

    onRejected:
    {
      if (!webRequest)
        return;

      var request = webRequest;
      webRequest = null;
      request.dialogReject();
    }
  }

  WebEngineView
  {
    id: web
    objectName: "web"
    width: mainWindow.width
    height: mainWindow.height
    z: 100
    backgroundColor: "transparent"

    // Keep the historical off-screen layer workaround on Linux where it
    // prevents intermittent black frames after minimize/resume. On Windows
    // the full WebEngineView layer forces an additional full-window texture
    // composition pass and makes large dialogs/pages noticeably sluggish.
    layer.enabled: !components.system.isWindows

    webChannel: webChannelObject
    settings.errorPageEnabled: false
    settings.localContentCanAccessRemoteUrls: true
    settings.localContentCanAccessFileUrls: true
    settings.allowRunningInsecureContent: true
    settings.playbackRequiresUserGesture: false
    profile.httpUserAgent: components.system.getUserAgent()
    profile.httpCacheType: WebEngineProfile.DiskHttpCache
    url: mainWindow.webUrl
    focus: true
    property string currentHoveredUrl: ""
    onLinkHovered: function(hoveredUrl)
    {
      web.currentHoveredUrl = hoveredUrl;
    }
    profile.persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
    profile.offTheRecord: false
    profile.storageName: "MinitigerDesktopStorage"

    Component.onCompleted:
    {
      console.log("WebEngineView size:", width, "x", height, "backgroundColor:", backgroundColor)
      forceActiveFocus()
      mainWindow.reloadWebClient.connect(reload)

      // Handle CSP workaround from C++
      components.system.pageContentReady.connect(function(html, finalUrl, hadCSP) {
        if (hadCSP) {
          console.log("CSP workaround: navigating to", finalUrl);
          web.url = finalUrl;
        }
      })

      var nativeshell =
      {
        sourceCode: components.system.getNativeShellScript(),
        injectionPoint: WebEngineScript.DocumentCreation,
        worldId: WebEngineScript.MainWorld
      }

      web.profile.userScripts.collection = [ nativeshell ];
    }

    onLoadingChanged: function(loadingInfo)
    {
      // we use a timer here to switch to the webview since
      // it take a few moments for the webview to render
      // after it has loaded.
      //
      if (loadingInfo.status == WebEngineView.LoadStartedStatus)
      {
        console.log("WebEngineLoadRequest starting: " + loadingInfo.url);
      }
      else if (loadingInfo.status == WebEngineView.LoadSucceededStatus)
      {
        console.log("WebEngineLoadRequest success: " + loadingInfo.url);
      }
      else if (loadingInfo.status == WebEngineView.LoadFailedStatus)
      {
        console.log("WebEngineLoadRequest failure: " + loadingInfo.url + " error code: " + loadingInfo.errorCode);
        errorLabel.visible = true
        errorLabel.text = "Error loading client, this is bad and should not happen<br>" +
                          "You can try to <a href='reload'>reload</a> or head to our <a href='http://jellyfin.org'>support page</a><br><br>Actual Error: <pre>" +
                          loadingInfo.errorString + " [" + loadingInfo.errorCode + "]</pre><br><br>" +
                          "Provide the <a target='_blank' href='file://"+ components.system.logFilePath + "'>logfile</a> as well."
      }
    }

    onNewWindowRequested:
    {
      if (request.userInitiated)
      {
        console.log("Opening external URL: " + web.currentHoveredUrl)
        components.system.openExternalUrl(web.currentHoveredUrl)
      }
    }

    onFullScreenRequested:
    {
      console.log("Request fullscreen: " + request.toggleOn)
      mainWindow.setFullScreen(request.toggleOn)
      request.accept()
    }

    onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID)
    {
      components.system.jsLog(level, sourceID + ":" + lineNumber + " " + message);
    }

    onCertificateError: function(error)
    {
      console.log(error.url + " :" + error.description + error.error)
      if (components.settings.ignoreSSLErrors()) {
        error.acceptCertificate()
      }
    }

    onFileDialogRequested: function(request)
    {
      if (request.mode !== FileDialogRequest.FileModeOpenMultiple)
        return;

      console.log("Handling WebEngine multi-file picker with native OpenFiles dialog");
      request.accepted = true;
      webMultipleFileDialog.webRequest = request;
      webMultipleFileDialog.open();
    }
  }

  Text
  {
    id: errorLabel
    z: 5
    anchors.centerIn: parent
    color: "#999999"
    linkColor: "#a85dc3"
    text: "Generic error"
    font.pixelSize: 32
    font.bold: true
    visible: false
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.StyledText
    onLinkActivated:
    {
      if (url == "reload")
      {
        errorLabel.visible = false
        web.reload()
      }
      else
      {
        Qt.openUrlExternally(url)
      }
    }
  }


  Rectangle
  {
    id: debug
    color: "black"
    z: 10
    anchors.centerIn: parent
    width: parent.width
    height: parent.height
    opacity: 0.7
    visible: mainWindow.showDebugLayer

    Text
    {
      id: debugLabel
      width: (parent.width - 50) / 2
      height: parent.height - 25
      anchors.left: parent.left
      anchors.leftMargin: 64
      anchors.top: parent.top
      anchors.topMargin: 54
      anchors.bottomMargin: 54
      color: "white"
      font.pixelSize: Math.round(height / 65)
      wrapMode: Text.WrapAnywhere

      function windowDebug()
      {
        var dbg = mainWindow.debugInfo + "Window and web\n";
        dbg += "  Window size: " + parent.width + "x" + parent.height + " - " + web.width + "x" + web.height + "\n";
        dbg += "  DevicePixel ratio: " + Screen.devicePixelRatio + "\n";

        return dbg;
      }

      text: windowDebug()
    }

    Text
    {
      id: videoLabel
      width: (parent.width - 50) / 2
      height: parent.height - 25
      anchors.right: parent.right
      anchors.left: debugLabel.right
      anchors.rightMargin: 64
      anchors.top: parent.top
      anchors.topMargin: 54
      anchors.bottomMargin: 54
      color: "white"
      font.pixelSize: Math.round(height / 65)
      wrapMode: Text.WrapAnywhere

      text: mainWindow.videoInfo
    }
  }

  property QtObject webChannel: web.webChannel

  Labs.SystemTrayIcon {
    visible: showSystemTrayIcon
    icon.source: "qrc:/images/icon.png"
    tooltip: "Minitiger Desktop"

    onActivated: function(reason) {
      if (reason === Labs.SystemTrayIcon.Context) {
        // Right click: open context menu
        contextMenu.open()
        components.window.setCursorVisibility(true)
      } else {
        // All other clicks: restore window
        restoreWindow()
      }
    }

    menu: Labs.Menu {
      id: contextMenu
      Labs.MenuItem {
        text: qsTr("Restore")
        onTriggered: restoreWindow()
      }
      Labs.MenuSeparator {}
      Labs.MenuItem {
        text: qsTr("Quit")
        onTriggered: Qt.quit()
      }
    }
  }
}
