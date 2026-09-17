import QtQuick
import Quickshell
import Quickshell.Io
import "DashlaneModel.js" as Model

Item {
  id: root

  // Injected by Omarchy shell
  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------------------
  // Views
  // ---------------------------------------------------------------------------
  property var views: []
  readonly property int viewCount: views.length

  function attachView(view) {
    if (!view || views.indexOf(view) !== -1) return;
    if (view.settings) updateSettings(view.settings);
    views = views.concat([view]);
    refreshStatus();
  }

  function detachView(view) {
    var next = [];
    for (var i = 0; i < views.length; i++) {
      if (views[i] !== view) next.push(views[i]);
    }
    views = next;
  }

  function updateSettings(s) {
    if (!s) return;
    if (s.autoLockMinutes !== undefined) autoLockMinutes = s.autoLockMinutes;
    if (s.lockOnScreenLock !== undefined) lockOnScreenLock = s.lockOnScreenLock;
    if (s.lockOnSuspend !== undefined) lockOnSuspend = s.lockOnSuspend;
    if (s.clearClipboardSec !== undefined) clearClipboardSec = s.clearClipboardSec;
    if (s.autoCopyTotpSec !== undefined) autoCopyTotpSec = s.autoCopyTotpSec;
    if (s.closeOnCopy !== undefined) closeOnCopy = s.closeOnCopy;
    if (s.suggestOnOpen !== undefined) suggestOnOpen = s.suggestOnOpen;
    if (s.colorizeIcon !== undefined) colorizeIcon = s.colorizeIcon;
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------
  property int autoLockMinutes: 15
  property bool lockOnScreenLock: true
  property bool lockOnSuspend: true
  property int clearClipboardSec: 30
  property int autoCopyTotpSec: 3
  property bool closeOnCopy: true
  property bool suggestOnOpen: true
  property bool colorizeIcon: false

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  property bool cliInstalled: false
  property bool loggedIn: false
  property bool locked: true
  property string userEmail: ""
  property bool syncing: false
  property string statusMessage: ""
  property string errorMessage: ""

  property var credentials: []
  property var notes: []
  property var secrets: []
  property var allItems: []
  property var filteredItems: []
  property var categories: [{ name: "All", count: 0 }]
  property string selectedCategory: "All"
  property string activeTab: "all" // "all", "logins", "notes", "secrets", "generator", "settings"
  property string searchQuery: ""

  property var selectedItem: null
  property var suggestedItem: null
  property var activeWindowData: null
  property var currentTotp: null

  property string lastCopiedPassword: ""
  property string pendingTotpCopy: ""
  property double lastActivityTimestamp: Date.now()

  // ---------------------------------------------------------------------------
  // Helpers & Filtering
  // ---------------------------------------------------------------------------
  function touchActivity() {
    lastActivityTimestamp = Date.now();
    if (autoLockMinutes > 0 && !locked && loggedIn) {
      autoLockTimer.restart();
    }
  }

  function recomputeFilter() {
    filteredItems = Model.filterItems(allItems, searchQuery, activeTab, selectedCategory);
  }

  function setSearchQuery(q) {
    searchQuery = q;
    touchActivity();
    recomputeFilter();
  }

  function setActiveTab(tab) {
    activeTab = tab;
    touchActivity();
    recomputeFilter();
    if (tab === "generator") {
      replenishEntropy();
    }
  }

  function setSelectedCategory(cat) {
    selectedCategory = cat;
    touchActivity();
    recomputeFilter();
  }

  function selectItem(item) {
    selectedItem = item;
    touchActivity();
    updateTotp();
  }

  function clearSelectedItem() {
    selectedItem = null;
    currentTotp = null;
    touchActivity();
  }

  function updateTotp() {
    if (!selectedItem || !selectedItem.hasOtp) {
      currentTotp = null;
      return;
    }
    var secret = selectedItem.otpSecret || selectedItem.otpUrl;
    if (secret) {
      currentTotp = Model.generateTotp(secret);
    } else {
      currentTotp = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Public Operations
  // ---------------------------------------------------------------------------
  function refreshStatus() {
    whichCliProc.running = true;
  }

  function refreshVault() {
    if (!loggedIn || locked) return;
    syncing = true;
    errorMessage = "";
    passwordsProc.running = true;
  }

  function unlockVault(masterPassword, callback) {
    if (!masterPassword || masterPassword.length === 0) {
      errorMessage = "Please enter your master password.";
      if (callback) callback(false, errorMessage);
      return;
    }
    syncing = true;
    errorMessage = "";
    unlockProc._masterPassword = masterPassword;
    unlockProc._callback = callback;
    unlockProc.command = Model.unlockCommand();
    unlockProc.running = true;
  }

  function lockVault() {
    lockProc.running = true;
  }

  function syncVault() {
    syncing = true;
    syncProc.running = true;
  }

  function logout() {
    logoutProc.running = true;
  }

  function launchTerminalSync() {
    terminalSyncProc.command = Model.terminalSyncCommand();
    terminalSyncProc.running = true;
  }

  function launchTerminalInstall() {
    terminalInstallProc.command = Model.terminalInstallCommand();
    terminalInstallProc.running = true;
  }

  function copyText(text, label, isSecret) {
    if (!text) return;
    touchActivity();
    copyProc.command = Model.copyCommand(text);
    copyProc.running = true;

    // Track secret text so clipboard auto-clearing can target only this value
    lastCopiedPassword = text;

    if (clearClipboardSec > 0) {
      clipboardClearTimer.interval = clearClipboardSec * 1000;
      clipboardClearTimer.restart();
    }

    notifyViews("Copied " + (label || "text") + " to clipboard");
  }

  function copyPassword(item) {
    if (!item || !item.password) return;
    copyText(item.password, "password for " + item.title, true);

    // Auto-copy TOTP follow up if configured
    if (item.hasOtp && autoCopyTotpSec > 0) {
      var otpObj = Model.generateTotp(item.otpSecret || item.otpUrl);
      if (otpObj && otpObj.code) {
        pendingTotpCopy = otpObj.code;
        autoCopyTotpTimer.interval = autoCopyTotpSec * 1000;
        autoCopyTotpTimer.restart();
      }
    }

    if (closeOnCopy) {
      closeAllViews();
    }
  }

  function copyUsername(item) {
    if (!item) return;
    var user = item.username || item.email;
    if (user) {
      copyText(user, "username for " + item.title, false);
      if (closeOnCopy) closeAllViews();
    }
  }

  function copyOtp(item) {
    if (!item) return;
    var otpObj = Model.generateTotp(item.otpSecret || item.otpUrl);
    if (otpObj && otpObj.code) {
      copyText(otpObj.code, "OTP code for " + item.title, true);
      if (closeOnCopy) closeAllViews();
    }
  }

  function openUrl(url) {
    if (!url) return;
    touchActivity();
    var cmd = Model.openUrlCommand(url);
    if (cmd) {
      openUrlProc.command = cmd;
      openUrlProc.running = true;
    }
  }

  function closeAllViews() {
    for (var i = 0; i < views.length; i++) {
      if (views[i] && typeof views[i].close === "function") {
        views[i].close();
      }
    }
  }

  function notifyViews(msg) {
    statusMessage = msg;
    clearStatusTimer.restart();
  }

  function checkActiveWindow() {
    if (suggestOnOpen && !locked && loggedIn) {
      activeWindowProc.running = true;
    }
  }

  function replenishEntropy() {
    if (!entropyProc.running) {
      entropyProc.running = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Background CLI Processes
  // ---------------------------------------------------------------------------

  // Check if dcli binary exists
  Process {
    id: whichCliProc
    command: Model.checkCliCommand()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = text.trim();
        root.cliInstalled = (path.length > 0);
        if (root.cliInstalled) {
          statusProc.running = true;
        } else {
          root.loggedIn = false;
          root.locked = true;
        }
      }
    }
  }

  // dcli status
  Process {
    id: statusProc
    command: Model.statusCommand()
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var parsed = Model.parseStatus(statusStdout.text);
      root.loggedIn = parsed.loggedIn;
      root.locked = parsed.locked;
      if (parsed.login) root.userEmail = parsed.login;

      if (root.loggedIn && !root.locked) {
        root.refreshVault();
      } else if (root.locked) {
        root.credentials = [];
        root.notes = [];
        root.secrets = [];
        root.allItems = [];
        root.filteredItems = [];
      }
    }
  }

  // dcli password -o json
  Process {
    id: passwordsProc
    command: Model.passwordsCommand()
    stdout: StdioCollector {
      id: passwordsStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.credentials = Model.parseJsonSafely(passwordsStdout.text, []);
      }
      notesProc.running = true;
    }
  }

  // dcli note -o json
  Process {
    id: notesProc
    command: Model.notesCommand()
    stdout: StdioCollector {
      id: notesStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.notes = Model.parseJsonSafely(notesStdout.text, []);
      }
      secretsProc.running = true;
    }
  }

  // dcli secret -o json
  Process {
    id: secretsProc
    command: Model.secretsCommand()
    stdout: StdioCollector {
      id: secretsStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.syncing = false;
      if (exitCode === 0) {
        root.secrets = Model.parseJsonSafely(secretsStdout.text, []);
      }

      root.allItems = Model.combineAndSortItems(root.credentials, root.notes, root.secrets);
      root.categories = Model.getCategories(root.allItems);
      root.recomputeFilter();
      root.checkActiveWindow();
    }
  }

  // Unlock process - feeds master password securely over stdin pipe, never via argv
  Process {
    id: unlockProc
    property string _masterPassword: ""
    property var _callback: null
    stdinEnabled: true

    onStarted: {
      write(_masterPassword + "\n");
      _masterPassword = ""; // zero out immediately
    }

    stdout: StdioCollector {
      id: unlockStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: unlockStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.syncing = false;
      _masterPassword = "";
      if (exitCode === 0) {
        root.locked = false;
        root.errorMessage = "";
        root.credentials = Model.parseJsonSafely(unlockStdout.text, []);
        root.refreshVault();
        if (_callback) _callback(true, "");
        root.notifyViews("Vault unlocked");
      } else {
        var err = unlockStderr.text.trim() || "Incorrect master password.";
        root.errorMessage = err;
        if (_callback) _callback(false, err);
      }
    }
  }

  // Lock process - wipes memory and scrubs clipboard
  Process {
    id: lockProc
    command: Model.lockCommand()
    onExited: function(exitCode) {
      root.locked = true;
      root.credentials = [];
      root.notes = [];
      root.secrets = [];
      root.allItems = [];
      root.filteredItems = [];
      root.selectedItem = null;
      root.currentTotp = null;
      root.searchQuery = "";
      root.lastCopiedPassword = "";
      root.pendingTotpCopy = "";
      autoCopyTotpTimer.stop();
      clipboardClearTimer.stop();

      // Immediately purge clipboard on lock
      clearClipboardProc.command = Model.clearClipboardCommand();
      clearClipboardProc.running = true;

      root.notifyViews("Vault locked");
    }
  }

  // Sync process
  Process {
    id: syncProc
    command: Model.syncCommand()
    onExited: function(exitCode) {
      root.syncing = false;
      if (exitCode === 0) {
        root.notifyViews("Vault synchronized");
        root.refreshVault();
      } else {
        root.notifyViews("Sync failed");
      }
    }
  }

  // Logout process
  Process {
    id: logoutProc
    command: Model.logoutCommand()
    onExited: function(exitCode) {
      root.loggedIn = false;
      root.locked = true;
      root.userEmail = "";
      root.credentials = [];
      root.notes = [];
      root.secrets = [];
      root.allItems = [];
      root.filteredItems = [];
      root.selectedItem = null;
      root.currentTotp = null;
      root.searchQuery = "";
      root.lastCopiedPassword = "";
      root.pendingTotpCopy = "";
      autoCopyTotpTimer.stop();
      clipboardClearTimer.stop();

      // Immediately purge clipboard on logout
      clearClipboardProc.command = Model.clearClipboardCommand();
      clearClipboardProc.running = true;

      root.notifyViews("Logged out of Dashlane");
    }
  }

  // Active window detection
  Process {
    id: activeWindowProc
    command: Model.activeWindowCommand()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var win = Model.parseJsonSafely(text, null);
        root.activeWindowData = win;
        root.suggestedItem = Model.matchActiveWindow(root.allItems, win);
      }
    }
  }

  // Screen lock monitoring process
  Process {
    id: screenLockProc
    command: Model.screenLockStateCommand()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (Model.screenIsLocked(text) && root.lockOnScreenLock && !root.locked && root.loggedIn) {
          root.lockVault();
        }
      }
    }
  }

  // System sleep/suspend monitor process
  Process {
    id: sleepMonitorProc
    command: Model.sleepMonitorCommand()
    stdout: SplitParser {
      onRead: function(line) {
        if (root.lockOnSuspend && !root.locked && root.loggedIn) {
          root.lockVault();
        }
      }
    }
  }

  // Hardware entropy feeder process for CSPRNG
  Process {
    id: entropyProc
    command: ["sh", "-c", "head -c 128 /dev/urandom | od -An -tu4 -v | tr -s ' ' '\n' | grep -v '^$' | head -n 32"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.trim().split(/\s+/);
        var ints = [];
        for (var i = 0; i < lines.length; i++) {
          var n = parseInt(lines[i], 10);
          if (!isNaN(n)) ints.push(n);
        }
        Model.feedEntropy(ints);
      }
    }
  }

  // Clipboard operations
  Process { id: copyProc }
  Process { id: clearClipboardProc }
  Process { id: openUrlProc }
  Process { id: terminalSyncProc }
  Process { id: terminalInstallProc }

  // ---------------------------------------------------------------------------
  // Timers
  // ---------------------------------------------------------------------------

  // Live TOTP countdown updater (ticks every second)
  Timer {
    id: totpTicker
    interval: 1000
    repeat: true
    running: root.selectedItem !== null && root.selectedItem.hasOtp
    onTriggered: root.updateTotp()
  }

  // Auto-lock inactivity timer
  Timer {
    id: autoLockTimer
    interval: root.autoLockMinutes * 60 * 1000
    repeat: false
    running: root.autoLockMinutes > 0 && !root.locked && root.loggedIn
    onTriggered: {
      if (!root.locked && root.loggedIn) {
        root.lockVault();
      }
    }
  }

  // Screen lock poll timer (polls every 3 seconds while vault is unlocked)
  Timer {
    id: screenLockPollTimer
    interval: 3000
    repeat: true
    running: root.lockOnScreenLock && !root.locked && root.loggedIn
    onTriggered: {
      if (!screenLockProc.running) {
        screenLockProc.running = true;
      }
    }
  }

  // Clipboard auto-clear timer
  Timer {
    id: clipboardClearTimer
    repeat: false
    onTriggered: {
      clearClipboardProc.command = Model.clearClipboardCommand(root.lastCopiedPassword);
      clearClipboardProc.running = true;
      root.lastCopiedPassword = "";
      root.notifyViews("Clipboard cleared");
    }
  }

  // Auto-copy TOTP delay timer
  Timer {
    id: autoCopyTotpTimer
    repeat: false
    onTriggered: {
      if (root.pendingTotpCopy) {
        root.copyText(root.pendingTotpCopy, "TOTP code", true);
        root.pendingTotpCopy = "";
      }
    }
  }

  // Toast / status message clear timer
  Timer {
    id: clearStatusTimer
    interval: 3500
    repeat: false
    onTriggered: root.statusMessage = ""
  }

  // Periodic status poll timer (every 60 seconds)
  Timer {
    id: periodicStatusTimer
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.refreshStatus()
  }

  onLockedChanged: {
    if (!locked && loggedIn && lockOnSuspend) {
      if (!sleepMonitorProc.running) {
        sleepMonitorProc.running = true;
      }
    } else {
      sleepMonitorProc.running = false;
    }
  }

  Component.onCompleted: {
    refreshStatus();
    replenishEntropy();
  }
}
