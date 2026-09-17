import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "DashlaneModel.js" as Model

Panel {
  id: root

  moduleName: "io.github.boeycorp.qs-dashlane-cli"
  ipcTarget: "io.github.boeycorp.qs-dashlane-cli"
  manageIpc: true

  // Shared background service (injected by Omarchy shell if running with service entry)
  property var service: null

  Loader {
    id: localServiceLoader
    active: root.service === null
    sourceComponent: Component {
      Service {
        id: localService
      }
    }
  }

  readonly property var vault: root.service || localServiceLoader.item

  // Local view state
  property int selectedIndex: 0
  property bool passwordRevealed: false
  property string generatorPassword: ""
  property int generatorLength: 20
  property bool generatorUpper: true
  property bool generatorLower: true
  property bool generatorNumbers: true
  property bool generatorSymbols: true
  property bool generatorNoAmbiguous: true
  property bool generatorPassphraseMode: false
  property int generatorWordCount: 4
  property string generatorSeparator: "-"

  function regeneratePassword() {
    if (generatorPassphraseMode) {
      generatorPassword = Model.generatePassphrase({
        wordCount: generatorWordCount,
        separator: generatorSeparator,
        capitalize: true
      });
    } else {
      generatorPassword = Model.generatePassword({
        length: generatorLength,
        uppercase: generatorUpper,
        lowercase: generatorLower,
        numbers: generatorNumbers,
        symbols: generatorSymbols,
        excludeAmbiguous: generatorNoAmbiguous
      });
    }
  }

  function moveSelection(delta) {
    if (!vault || !vault.filteredItems || vault.filteredItems.length === 0) {
      selectedIndex = 0;
      return;
    }
    var count = vault.filteredItems.length;
    var next = selectedIndex + delta;
    if (next < 0) next = 0;
    if (next >= count) next = count - 1;
    selectedIndex = next;
    if (itemsListView) {
      itemsListView.positionViewAtIndex(selectedIndex, ListView.Contain);
    }
  }

  function activateCurrentSelection() {
    if (!vault || !vault.filteredItems || vault.filteredItems.length === 0) return;
    if (selectedIndex >= 0 && selectedIndex < vault.filteredItems.length) {
      var item = vault.filteredItems[selectedIndex];
      if (item.type === "login") {
        vault.copyPassword(item);
      } else if (item.type === "secret") {
        vault.copyText(item.password, "secret for " + item.title, true);
      } else if (item.type === "note") {
        vault.copyText(item.note, "note for " + item.title, false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Bar Widget Button
  // ---------------------------------------------------------------------------
  WidgetButton {
    id: button
    bar: root.bar
    text: "󰌋" // Nerd Font key icon
    active: root.opened
    tooltipText: {
      if (!vault) return "Dashlane";
      if (!vault.cliInstalled) return "Dashlane (CLI not installed)";
      if (!vault.loggedIn) return "Dashlane (Not signed in)";
      if (vault.locked) return "Dashlane (Locked)";
      return "Dashlane (" + (vault.userEmail || "Unlocked") + ")";
    }

    foreground: {
      if (!vault) return Color.foreground;
      if (vault.colorizeIcon && Color.accent) return Color.accent;
      if (vault.locked) return Qt.darker(Color.foreground, 1.4);
      return Color.foreground;
    }

    // Small status indicator dot inside the button
    Rectangle {
      width: Style.space(5)
      height: Style.space(5)
      radius: Style.space(3)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(5)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      visible: vault !== null && vault.loggedIn
      color: vault.locked ? (Color.urgent || "#e06c75") : (Color.accent || "#98c379")
    }

    onPressed: function(btn) {
      if (btn === Qt.RightButton) {
        if (vault && vault.loggedIn && !vault.locked) {
          vault.syncVault();
        } else if (vault && vault.loggedIn && vault.locked) {
          root.open();
        }
      } else {
        root.toggle();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Popout Panel
  // ---------------------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher

    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(620))

    onOpenChanged: {
      if (open && vault) {
        vault.touchActivity();
        vault.checkActiveWindow();
        if (generatorPassword === "") {
          regeneratePassword();
        }
        if (vault.loggedIn && !vault.locked) {
          Qt.callLater(function() {
            if (searchField && searchField.visible) {
              searchField.forceActiveFocus();
            }
          });
        } else if (vault.loggedIn && vault.locked) {
          Qt.callLater(function() {
            if (unlockPasswordField && unlockPasswordField.visible) {
              unlockPasswordField.forceActiveFocus();
            }
          });
        }
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: {
        if (vault && vault.selectedItem !== null) {
          vault.clearSelectedItem();
        } else if (searchField && searchField.text.length > 0) {
          searchField.text = "";
          vault.setSearchQuery("");
        } else {
          root.close();
        }
      }

      onMoveRequested: function(dx, dy) {
        if (dy !== 0 && vault && vault.selectedItem === null && vault.activeTab !== "generator" && vault.activeTab !== "settings") {
          root.moveSelection(dy);
        }
      }

      onActivateRequested: {
        if (vault && vault.selectedItem === null && vault.activeTab !== "generator" && vault.activeTab !== "settings") {
          root.activateCurrentSelection();
        }
      }

      onTabRequested: function(direction) {
        root.switchPanel(direction);
      }

      Flickable {
        id: flickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: mainColumn
          width: flickable.width
          spacing: Style.space(10)
          padding: Style.space(14)

          // -----------------------------------------------------------------
          // Header Bar
          // -----------------------------------------------------------------
          RowLayout {
            width: parent.width - Style.space(28)
            spacing: Style.space(8)

            Text {
              text: "󰌋"
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              color: Color.accent || Color.foreground
            }

            Text {
              text: "Dashlane"
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              color: Color.foreground
            }

            // Syncing indicator
            Text {
              text: "󰑐"
              font.family: Style.font.family
              font.pixelSize: Style.font.small
              color: Color.accent
              visible: vault && vault.syncing
              RotationAnimation on rotation {
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
                running: vault && vault.syncing
              }
            }

            Item { Layout.fillWidth: true }

            // User Email pill
            Rectangle {
              height: Style.space(22)
              width: userEmailText.implicitWidth + Style.space(12)
              radius: Style.cornerRadius
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
              visible: vault && vault.loggedIn && vault.userEmail.length > 0

              Text {
                id: userEmailText
                anchors.centerIn: parent
                text: vault ? vault.userEmail : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Qt.darker(Color.foreground, 1.2)
                elide: Text.ElideMiddle
                maximumLineCount: 1
              }
            }

            // Manual Sync Button
            Button {
              iconText: "󰑐"
              tooltipText: "Sync Vault"
              visible: vault && vault.loggedIn && !vault.locked
              onClicked: vault.syncVault()
            }

            // Lock Button
            Button {
              iconText: "󰌾"
              tooltipText: "Lock Vault"
              visible: vault && vault.loggedIn && !vault.locked
              onClicked: vault.lockVault()
            }

            // Settings toggle button
            Button {
              iconText: "󰒓"
              tooltipText: "Settings"
              visible: vault && vault.loggedIn
              selected: vault && vault.activeTab === "settings"
              onClicked: {
                if (vault.activeTab === "settings") {
                  vault.setActiveTab("all");
                } else {
                  vault.setActiveTab("settings");
                }
              }
            }

            // Close button
            Button {
              iconText: "✕"
              tooltipText: "Close"
              onClicked: root.close()
            }
          }

          // -----------------------------------------------------------------
          // Toast / Notification Banner
          // -----------------------------------------------------------------
          Rectangle {
            width: parent.width - Style.space(28)
            height: Style.space(30)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
            border.width: 1
            visible: vault && vault.statusMessage.length > 0

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)

              Text {
                text: "󰄬"
                font.family: Style.font.family
                font.pixelSize: Style.font.small
                color: Color.accent
              }

              Text {
                Layout.fillWidth: true
                text: vault ? vault.statusMessage : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.foreground
                elide: Text.ElideRight
              }
            }
          }

          PanelSeparator {
            width: parent.width - Style.space(28)
          }

          // =================================================================
          // Screen 1: CLI Not Installed
          // =================================================================
          Column {
            width: parent.width - Style.space(28)
            spacing: Style.space(14)
            visible: vault && !vault.cliInstalled

            Rectangle {
              width: parent.width
              height: Style.space(70)
              radius: Style.cornerRadius
              color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.12)
              border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.3)
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(12)

                Text {
                  text: "󰀪"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(26)
                  color: Color.urgent
                }

                Column {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    text: "Dashlane CLI Not Found"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    color: Color.foreground
                  }

                  Text {
                    text: "Install the official 'dcli' package to access your passwords."
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Qt.darker(Color.foreground, 1.3)
                  }
                }
              }
            }

            Button {
              width: parent.width
              text: "Install Dashlane CLI"
              iconText: "󰇚"
              bordered: true
              accent: Color.accent
              onClicked: vault.launchTerminalInstall()
            }

            Button {
              width: parent.width
              text: "Check Again"
              iconText: "󰑐"
              onClicked: vault.refreshStatus()
            }

            Text {
              width: parent.width
              text: "Or install manually in terminal via yay -S dcli-git or npm install -g @dashlane/cli"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.foreground, 1.5)
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // =================================================================
          // Screen 2: Logged Out
          // =================================================================
          Column {
            width: parent.width - Style.space(28)
            spacing: Style.space(14)
            visible: vault && vault.cliInstalled && !vault.loggedIn

            Item { width: 1; height: Style.space(10) }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰌋"
              font.family: Style.font.family
              font.pixelSize: Style.space(46)
              color: Color.accent
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Connect to Dashlane"
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              color: Color.foreground
            }

            Text {
              width: parent.width
              text: "Log in with your Dashlane account to access and search your vault directly from your status bar."
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: Qt.darker(Color.foreground, 1.3)
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            Item { width: 1; height: Style.space(6) }

            Button {
              width: parent.width
              text: "Log in via Terminal (2FA & SSO)"
              iconText: "󰌾"
              bordered: true
              accent: Color.accent
              onClicked: vault.launchTerminalSync()
            }

            Text {
              width: parent.width
              text: "Uses 1st-party Dashlane CLI with OS keyring storage for maximum security."
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.foreground, 1.6)
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // =================================================================
          // Screen 3: Vault Locked
          // =================================================================
          Column {
            width: parent.width - Style.space(28)
            spacing: Style.space(12)
            visible: vault && vault.cliInstalled && vault.loggedIn && vault.locked

            Item { width: 1; height: Style.space(6) }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰌾"
              font.family: Style.font.family
              font.pixelSize: Style.space(40)
              color: Color.urgent || "#e06c75"
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Unlock Vault"
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              color: Color.foreground
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: vault ? vault.userEmail : ""
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.foreground, 1.4)
            }

            Item { width: 1; height: Style.space(6) }

            // Master Password Input
            TextField {
              id: unlockPasswordField
              width: parent.width
              password: true
              placeholderText: "Enter Master Password..."
              onAccepted: {
                vault.unlockVault(text, function(success, err) {
                  if (success) {
                    text = "";
                  }
                });
              }
            }

            // Error message display
            Text {
              width: parent.width
              text: vault ? vault.errorMessage : ""
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.urgent || "#e06c75"
              wrapMode: Text.WordWrap
              visible: vault && vault.errorMessage.length > 0
            }

            Button {
              width: parent.width
              text: vault && vault.syncing ? "Unlocking..." : "Unlock Vault"
              iconText: "󰌋"
              bordered: true
              accent: Color.accent
              onClicked: {
                vault.unlockVault(unlockPasswordField.text, function(success, err) {
                  if (success) {
                    unlockPasswordField.text = "";
                  }
                });
              }
            }

            PanelSeparator { width: parent.width }

            Button {
              width: parent.width
              text: "Unlock with Terminal"
              iconText: "󰆍"
              onClicked: vault.launchTerminalSync()
            }
          }

          // =================================================================
          // Screen 4: Vault Unlocked
          // =================================================================
          Column {
            width: parent.width - Style.space(28)
            spacing: Style.space(10)
            visible: vault && vault.cliInstalled && vault.loggedIn && !vault.locked

            // ---------------------------------------------------------------
            // 4A: Item Detail View
            // ---------------------------------------------------------------
            Column {
              width: parent.width
              spacing: Style.space(12)
              visible: vault && vault.selectedItem !== null

              // Back button
              Button {
                text: "Back to items"
                iconText: "󰅁"
                onClicked: {
                  root.passwordRevealed = false;
                  vault.clearSelectedItem();
                }
              }

              // Item Title & Category
              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: vault && vault.selectedItem && vault.selectedItem.type === "login" ? "󰌋"
                      : (vault && vault.selectedItem && vault.selectedItem.type === "note" ? "󰎚" : "󰞀")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  color: Color.accent
                }

                Column {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: vault && vault.selectedItem ? vault.selectedItem.title : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    color: Color.foreground
                    elide: Text.ElideRight
                  }

                  Text {
                    text: vault && vault.selectedItem ? vault.selectedItem.category : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Qt.darker(Color.foreground, 1.4)
                  }
                }
              }

              PanelSeparator { width: parent.width }

              // Website URL (if present)
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: vault && vault.selectedItem && vault.selectedItem.url.length > 0

                PanelSectionHeader { text: "WEBSITE" }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    Layout.fillWidth: true
                    text: vault && vault.selectedItem ? vault.selectedItem.url : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    color: Color.accent
                    elide: Text.ElideRight
                  }

                  Button {
                    iconText: "󰌹"
                    tooltipText: "Open in browser"
                    onClicked: vault.openUrl(vault.selectedItem.url)
                  }
                }
              }

              // Username / Login (if present)
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: vault && vault.selectedItem && (vault.selectedItem.username.length > 0 || vault.selectedItem.email.length > 0)

                PanelSectionHeader { text: "USERNAME / LOGIN" }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    Layout.fillWidth: true
                    text: vault && vault.selectedItem ? (vault.selectedItem.username || vault.selectedItem.email) : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    color: Color.foreground
                    elide: Text.ElideRight
                  }

                  Button {
                    iconText: "󰈎"
                    tooltipText: "Copy Username"
                    onClicked: vault.copyUsername(vault.selectedItem)
                  }
                }
              }

              // Password (if present)
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: vault && vault.selectedItem && vault.selectedItem.password.length > 0

                PanelSectionHeader { text: "PASSWORD" }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    Layout.fillWidth: true
                    text: root.passwordRevealed ? (vault ? vault.selectedItem.password : "") : "••••••••••••••••"
                    font.family: root.passwordRevealed ? Style.font.family : "monospace"
                    font.pixelSize: Style.font.body
                    color: Color.foreground
                    elide: Text.ElideRight
                  }

                  Button {
                    iconText: root.passwordRevealed ? "󰈈" : "󰈉"
                    tooltipText: root.passwordRevealed ? "Hide password" : "Show password"
                    onClicked: root.passwordRevealed = !root.passwordRevealed
                  }

                  Button {
                    iconText: "󰈔"
                    tooltipText: "Copy Password"
                    onClicked: vault.copyPassword(vault.selectedItem)
                  }
                }
              }

              // TOTP 2FA (if item has OTP)
              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: vault && vault.selectedItem && vault.selectedItem.hasOtp

                PanelSectionHeader { text: "ONE-TIME PASSCODE (2FA)" }

                Rectangle {
                  width: parent.width
                  height: Style.space(56)
                  radius: Style.cornerRadius
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.1)
                  border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)
                  border.width: 1

                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    spacing: Style.space(12)

                    Text {
                      text: "󰝥"
                      font.family: Style.font.family
                      font.pixelSize: Style.space(22)
                      color: Color.accent
                    }

                    Column {
                      Layout.fillWidth: true
                      spacing: Style.space(2)

                      Text {
                        text: vault && vault.currentTotp ? vault.currentTotp.code : "------"
                        font.family: "monospace"
                        font.pixelSize: Style.space(20)
                        font.bold: true
                        color: Color.foreground
                      }

                      Text {
                        text: (vault && vault.currentTotp ? vault.currentTotp.remainingSeconds : 0) + "s remaining"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: Qt.darker(Color.foreground, 1.4)
                      }
                    }

                    Button {
                      iconText: "󰈔"
                      tooltipText: "Copy OTP Code"
                      onClicked: vault.copyOtp(vault.selectedItem)
                    }
                  }
                }
              }

              // Secure Note / Secret Content
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: vault && vault.selectedItem && (vault.selectedItem.content.length > 0 || vault.selectedItem.note.length > 0)

                PanelSectionHeader { text: "CONTENT / NOTES" }

                Rectangle {
                  width: parent.width
                  height: Math.min(Style.space(160), Math.max(Style.space(60), noteText.implicitHeight + Style.space(16)))
                  radius: Style.cornerRadius
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
                  border.width: 1

                  Flickable {
                    anchors.fill: parent
                    anchors.margins: Style.space(8)
                    contentWidth: width
                    contentHeight: noteText.implicitHeight
                    clip: true

                    Text {
                      id: noteText
                      width: parent.width
                      text: vault && vault.selectedItem ? (vault.selectedItem.content || vault.selectedItem.note) : ""
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption
                      color: Color.foreground
                      wrapMode: Text.WrapAnywhere
                    }
                  }
                }

                Button {
                  width: parent.width
                  text: "Copy Note Content"
                  iconText: "󰈔"
                  onClicked: {
                    var c = vault.selectedItem.content || vault.selectedItem.note;
                    vault.copyText(c, "content for " + vault.selectedItem.title, false);
                  }
                }
              }
            }

            // ---------------------------------------------------------------
            // 4B: Password Generator View
            // ---------------------------------------------------------------
            Column {
              width: parent.width
              spacing: Style.space(12)
              visible: vault && vault.selectedItem === null && vault.activeTab === "generator"

              PanelSectionHeader { text: "PASSWORD GENERATOR" }

              // Generated password display card
              Rectangle {
                width: parent.width
                height: Style.space(56)
                radius: Style.cornerRadius
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    Layout.fillWidth: true
                    text: root.generatorPassword
                    font.family: "monospace"
                    font.pixelSize: Style.font.body
                    font.bold: true
                    color: Color.foreground
                    elide: Text.ElideRight
                  }

                  Button {
                    iconText: "󰑐"
                    tooltipText: "Regenerate"
                    onClicked: root.regeneratePassword()
                  }

                  Button {
                    iconText: "󰈔"
                    tooltipText: "Copy Password"
                    onClicked: vault.copyText(root.generatorPassword, "generated password", true)
                  }
                }
              }

              // Strength Meter
              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                Rectangle {
                  Layout.fillWidth: true
                  height: Style.space(6)
                  radius: Style.space(3)
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)

                  Rectangle {
                    width: parent.width * (Model.calculateStrength(root.generatorPassword).percent || 0.5)
                    height: parent.height
                    radius: parent.radius
                    color: {
                      var s = Model.calculateStrength(root.generatorPassword).score;
                      if (s >= 80) return Color.accent || "#98c379";
                      if (s >= 60) return "#e5c07b";
                      return Color.urgent || "#e06c75";
                    }
                  }
                }

                Text {
                  text: Model.calculateStrength(root.generatorPassword).label
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: Color.foreground
                }
              }

              PanelSeparator { width: parent.width }

              // Controls
              RowLayout {
                width: parent.width
                Text {
                  Layout.fillWidth: true
                  text: root.generatorPassphraseMode ? ("Word Count: " + root.generatorWordCount) : ("Length: " + root.generatorLength)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Color.foreground
                }
              }

              PanelSlider {
                width: parent.width
                bar: root.bar
                minimum: root.generatorPassphraseMode ? 3 : 8
                maximum: root.generatorPassphraseMode ? 8 : 64
                step: 1
                integer: true
                value: root.generatorPassphraseMode ? root.generatorWordCount : root.generatorLength
                onMoved: function(v) {
                  if (root.generatorPassphraseMode) {
                    root.generatorWordCount = Math.round(v);
                  } else {
                    root.generatorLength = Math.round(v);
                  }
                  root.regeneratePassword();
                }
              }

              // Passphrase mode switch
              RowLayout {
                width: parent.width
                Text {
                  Layout.fillWidth: true
                  text: "Passphrase mode"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Color.foreground
                }
                ToggleSwitch {
                  checked: root.generatorPassphraseMode
                  onToggled: {
                    root.generatorPassphraseMode = !root.generatorPassphraseMode;
                    root.regeneratePassword();
                  }
                }
              }

              // Character Toggles (shown when not passphrase mode)
              Column {
                width: parent.width
                spacing: Style.space(8)
                visible: !root.generatorPassphraseMode

                RowLayout {
                  width: parent.width
                  Text { Layout.fillWidth: true; text: "Uppercase (A-Z)"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.foreground }
                  ToggleSwitch { checked: root.generatorUpper; onToggled: { root.generatorUpper = !root.generatorUpper; root.regeneratePassword() } }
                }
                RowLayout {
                  width: parent.width
                  Text { Layout.fillWidth: true; text: "Lowercase (a-z)"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.foreground }
                  ToggleSwitch { checked: root.generatorLower; onToggled: { root.generatorLower = !root.generatorLower; root.regeneratePassword() } }
                }
                RowLayout {
                  width: parent.width
                  Text { Layout.fillWidth: true; text: "Numbers (0-9)"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.foreground }
                  ToggleSwitch { checked: root.generatorNumbers; onToggled: { root.generatorNumbers = !root.generatorNumbers; root.regeneratePassword() } }
                }
                RowLayout {
                  width: parent.width
                  Text { Layout.fillWidth: true; text: "Symbols (!@#$)"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.foreground }
                  ToggleSwitch { checked: root.generatorSymbols; onToggled: { root.generatorSymbols = !root.generatorSymbols; root.regeneratePassword() } }
                }
                RowLayout {
                  width: parent.width
                  Text { Layout.fillWidth: true; text: "Avoid ambiguous characters (0, O, l, 1)"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.foreground }
                  ToggleSwitch { checked: root.generatorNoAmbiguous; onToggled: { root.generatorNoAmbiguous = !root.generatorNoAmbiguous; root.regeneratePassword() } }
                }
              }

              Button {
                width: parent.width
                text: "Copy Generated Password"
                iconText: "󰈔"
                bordered: true
                accent: Color.accent
                onClicked: vault.copyText(root.generatorPassword, "generated password", true)
              }
            }

            // ---------------------------------------------------------------
            // 4C: Settings View
            // ---------------------------------------------------------------
            Column {
              width: parent.width
              spacing: Style.space(12)
              visible: vault && vault.selectedItem === null && vault.activeTab === "settings"

              PanelSectionHeader { text: "VAULT SETTINGS" }

              RowLayout {
                width: parent.width
                Text {
                  Layout.fillWidth: true
                  text: "Auto-lock timeout: " + (vault ? vault.autoLockMinutes : 15) + " min"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Color.foreground
                }
              }

              PanelSlider {
                width: parent.width
                bar: root.bar
                minimum: 0
                maximum: 120
                step: 5
                integer: true
                value: vault ? vault.autoLockMinutes : 15
                onMoved: function(v) { if (vault) vault.autoLockMinutes = Math.round(v) }
              }

              RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: "Lock on screen lock"; font.family: Style.font.family; font.pixelSize: Style.font.body; color: Color.foreground }
                ToggleSwitch {
                  checked: vault ? vault.lockOnScreenLock : true
                  onToggled: if (vault) vault.lockOnScreenLock = !vault.lockOnScreenLock
                }
              }

              RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: "Lock on system suspend"; font.family: Style.font.family; font.pixelSize: Style.font.body; color: Color.foreground }
                ToggleSwitch {
                  checked: vault ? vault.lockOnSuspend : true
                  onToggled: if (vault) vault.lockOnSuspend = !vault.lockOnSuspend
                }
              }

              RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: "Contextual active-window suggestions"; font.family: Style.font.family; font.pixelSize: Style.font.body; color: Color.foreground }
                ToggleSwitch {
                  checked: vault ? vault.suggestOnOpen : true
                  onToggled: if (vault) vault.suggestOnOpen = !vault.suggestOnOpen
                }
              }

              RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: "Colorize status-bar icon"; font.family: Style.font.family; font.pixelSize: Style.font.body; color: Color.foreground }
                ToggleSwitch {
                  checked: vault ? vault.colorizeIcon : false
                  onToggled: if (vault) vault.colorizeIcon = !vault.colorizeIcon
                }
              }

              PanelSeparator { width: parent.width }

              PanelSectionHeader { text: "ACTIONS" }

              Button {
                width: parent.width
                text: "Sync Vault Now"
                iconText: "󰑐"
                onClicked: vault.syncVault()
              }

              Button {
                width: parent.width
                text: "Lock Vault"
                iconText: "󰌾"
                onClicked: vault.lockVault()
              }

              Button {
                width: parent.width
                text: "Log Out of Dashlane"
                iconText: "󰗽"
                foreground: Color.urgent || "#e06c75"
                onClicked: vault.logout()
              }
            }

            // ---------------------------------------------------------------
            // 4D: Vault List View (Default)
            // ---------------------------------------------------------------
            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: vault && vault.selectedItem === null && vault.activeTab !== "generator" && vault.activeTab !== "settings"

              // Tabs Row
              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: [
                    { id: "all", label: "All" },
                    { id: "logins", label: "Logins" },
                    { id: "notes", label: "Notes" },
                    { id: "secrets", label: "Secrets" },
                    { id: "generator", label: "Generator" }
                  ]

                  Button {
                    text: modelData.label
                    selected: vault ? vault.activeTab === modelData.id : false
                    onClicked: {
                      vault.setActiveTab(modelData.id);
                      if (modelData.id === "generator") {
                        root.regeneratePassword();
                      }
                    }
                  }
                }
              }

              // Search Field
              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: searchField
                  Layout.fillWidth: true
                  placeholderText: "Search vault (name, user, domain)..."
                  onTextChanged: {
                    vault.setSearchQuery(text);
                    root.selectedIndex = 0;
                  }
                  onAccepted: {
                    root.activateCurrentSelection();
                  }
                }

                Button {
                  iconText: "✕"
                  tooltipText: "Clear search"
                  visible: searchField.text.length > 0
                  onClicked: {
                    searchField.text = "";
                    vault.setSearchQuery("");
                  }
                }
              }

              // Category Pills (if more than 1 category)
              Flickable {
                width: parent.width
                height: Style.space(26)
                contentWidth: categoryRow.implicitWidth
                clip: true
                visible: vault && vault.categories && vault.categories.length > 1

                Row {
                  id: categoryRow
                  spacing: Style.space(6)

                  Repeater {
                    model: vault ? vault.categories : []

                    Rectangle {
                      height: Style.space(24)
                      width: catText.implicitWidth + Style.space(16)
                      radius: Style.cornerRadius
                      color: (vault && vault.selectedCategory === modelData.name)
                        ? (Color.accent || "#98c379")
                        : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)

                      Text {
                        id: catText
                        anchors.centerIn: parent
                        text: modelData.name + " (" + modelData.count + ")"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: (vault && vault.selectedCategory === modelData.name)
                          ? (Color.background || "#111")
                          : Color.foreground
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: vault.setSelectedCategory(modelData.name)
                      }
                    }
                  }
                }
              }

              // Contextual Suggestion Banner
              Rectangle {
                width: parent.width
                height: Style.space(48)
                radius: Style.cornerRadius
                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
                border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
                border.width: 1
                visible: vault && vault.suggestedItem !== null && searchField.text.length === 0

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    text: "󰌋"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    color: Color.accent
                  }

                  Column {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Row {
                      spacing: Style.space(4)
                      Text {
                        text: "Suggested:"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: Color.accent
                      }
                      Text {
                        text: vault && vault.suggestedItem ? vault.suggestedItem.title : ""
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: Color.foreground
                        elide: Text.ElideRight
                      }
                    }

                    Text {
                      text: vault && vault.suggestedItem ? (vault.suggestedItem.username || vault.suggestedItem.email) : ""
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      color: Qt.darker(Color.foreground, 1.3)
                      elide: Text.ElideRight
                    }
                  }

                  Button {
                    iconText: "󰈔"
                    tooltipText: "Copy Password"
                    onClicked: vault.copyPassword(vault.suggestedItem)
                  }

                  Button {
                    iconText: "󰅂"
                    tooltipText: "View Details"
                    onClicked: vault.selectItem(vault.suggestedItem)
                  }
                }
              }

              // Items ListView
              ListView {
                id: itemsListView
                width: parent.width
                height: Math.min(Style.space(380), Math.max(Style.space(120), count * Style.space(52)))
                clip: true
                model: vault ? vault.filteredItems : []

                delegate: Rectangle {
                  width: itemsListView.width
                  height: Style.space(48)
                  radius: Style.cornerRadius
                  color: index === root.selectedIndex
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                    : (itemMouseArea.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05) : "transparent")

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(10)

                    // Type icon
                    Text {
                      text: modelData.type === "login" ? "󰌋" : (modelData.type === "note" ? "󰎚" : "󰞀")
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      color: modelData.type === "login" ? Color.accent : (Color.foreground)
                    }

                    // Title & Username/Category
                    Column {
                      Layout.fillWidth: true
                      spacing: Style.space(1)

                      Text {
                        width: parent.width
                        text: modelData.title
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: index === root.selectedIndex
                        color: Color.foreground
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        text: (modelData.username || modelData.email || modelData.category || "")
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: Qt.darker(Color.foreground, 1.4)
                        elide: Text.ElideRight
                      }
                    }

                    // Copy Password / Content button
                    Button {
                      iconText: "󰈔"
                      tooltipText: modelData.type === "login" ? "Copy Password" : "Copy Content"
                      onClicked: {
                        if (modelData.type === "login") {
                          vault.copyPassword(modelData);
                        } else if (modelData.type === "secret") {
                          vault.copyText(modelData.password, "secret for " + modelData.title, true);
                        } else {
                          vault.copyText(modelData.note, "note for " + modelData.title, false);
                        }
                      }
                    }

                    // Copy Username button (for logins)
                    Button {
                      iconText: "󰈎"
                      tooltipText: "Copy Username"
                      visible: modelData.type === "login" && (modelData.username.length > 0 || modelData.email.length > 0)
                      onClicked: vault.copyUsername(modelData)
                    }

                    // Copy OTP button (if item has OTP)
                    Button {
                      iconText: "󰝥"
                      tooltipText: "Copy OTP Code"
                      visible: modelData.hasOtp
                      onClicked: vault.copyOtp(modelData)
                    }

                    // Open details button
                    Button {
                      iconText: "󰅂"
                      tooltipText: "View Details"
                      onClicked: {
                        root.passwordRevealed = false;
                        vault.selectItem(modelData);
                      }
                    }
                  }

                  MouseArea {
                    id: itemMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                      root.selectedIndex = index;
                      root.passwordRevealed = false;
                      vault.selectItem(modelData);
                    }
                  }
                }

                // Empty State
                Text {
                  anchors.centerIn: parent
                  text: vault && vault.filteredItems && vault.filteredItems.length === 0 ? "No vault items found" : ""
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Qt.darker(Color.foreground, 1.5)
                  visible: vault && vault.filteredItems && vault.filteredItems.length === 0
                }
              }
            }
          }
        }
      }
    }
  }

  Component.onCompleted: {
    if (vault) {
      vault.attachView(root);
    }
  }

  Component.onDestruction: {
    if (vault) {
      vault.detachView(root);
    }
  }
}
