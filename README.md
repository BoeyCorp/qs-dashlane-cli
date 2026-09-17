# qs-dashlane-cli

Your Dashlane vault in the **Omarchy** status bar. Search, copy passwords & 2FA OTP codes, manage secure notes, secrets, and generate passwords without ever leaving your workflow.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: Omarchy](https://img.shields.io/badge/platform-Omarchy%20%2F%20Hyprland-7c3aed.svg)](https://omarchy.org/)
[![Requires: Dashlane CLI](https://img.shields.io/badge/requires-Dashlane%20CLI%20(dcli)-0e8a16.svg)](https://cli.dashlane.com/)
[![Built with Quickshell](https://img.shields.io/badge/built%20with-Quickshell-ff69b4.svg)](https://quickshell.outfoxxed.me/)

Built for [Omarchy](https://omarchy.org/) on Quickshell and the official [Dashlane CLI (`dcli`)](https://cli.dashlane.com/). Keyboard-first, lightning fast, and integrates seamlessly with Linux Secret Service / OS keyring.

---

## Quick Install

One command installs and enables the plugin in your Omarchy status bar:

```bash
omarchy plugin add https://github.com/BoeyCorp/qs-dashlane-cli --enable
```

To update in the future:
```bash
omarchy plugin update io.github.boeycorp.qs-dashlane-cli
```

---

## Features Tour

### ⚡ Vault at Your Fingertips
- Instant search across login names, usernames, emails, URLs, notes, and categories.
- <kbd>Enter</kbd> immediately copies the password to your clipboard.
- Keyboard navigation: use <kbd>↑</kbd> / <kbd>↓</kbd> arrows to move between items, <kbd>Esc</kbd> to clear or close.

### 🎯 Contextual Password Suggestions
- Reads the focused window and browser tab using Hyprland IPC.
- If you're on `github.com` or in the Discord app, your matching credential is automatically pinned to the top of the panel.

### 🔢 Real-Time 2FA TOTP Codes
- Built-in RFC 6238 TOTP generator with a live 30-second countdown.
- 1-click copy for one-time verification passcodes.
- Optional automatic copy of TOTP code shortly after copying a password.

### 🔐 1st-Party Dashlane CLI & OS Keyring Integration
- Utilizes the official 1st-party [Dashlane CLI (`dcli`)](https://cli.dashlane.com/).
- Stores decrypted keys safely in the Linux OS keyring (`libsecret` / Secret Service), never unencrypted on disk.
- In-panel Master Password unlocking with support for terminal login (SSO, Duo Push, hardware keys, and 2FA tokens).

### 📝 Passwords, Secure Notes & Developer Secrets
- Filter seamlessly across **Logins**, **Secure Notes**, and **Secrets** (API keys, SSH tokens).
- Category chips for filtering by project, organization, or tag.
- Masked sensitive fields with instant reveal toggle and 1-click clipboard copy.

### 🎲 Password & Passphrase Generator
- Cryptographically secure password generator with live strength meter.
- Configurable length (8–64 characters) and character sets (uppercase, lowercase, numbers, symbols, and avoid ambiguous characters).
- **Passphrase mode**: generate memorable passphrases with custom word count and separators.

### 🛡️ Hardened Security
- **Auto-lock timeout**: locks vault automatically after configurable minutes of inactivity.
- **Lock on screen lock**: locks immediately when the Omarchy lock screen activates.
- **Lock on suspend**: drops decrypted memory keys before your system goes to sleep.
- **Clipboard auto-clear**: automatically wipes copied credentials from the clipboard after 30 seconds.

---

## Prerequisites

The plugin interfaces with the official 1st-party Dashlane CLI (`dcli`).

### Install Dashlane CLI (`dcli`)

You can install `dcli` using your preferred method on Arch Linux / Omarchy:

#### Via AUR (Recommended)
```bash
omarchy pkg aur add dcli-git
# or with yay:
yay -S dcli-git
```

#### Via npm
```bash
sudo npm install -g @dashlane/cli
```

#### Via Direct Binary
Download the official prebuilt binary `dcli-linux-x64` from [Dashlane CLI Releases](https://github.com/Dashlane/dashlane-cli/releases) and place it in your `~/.local/bin/dcli` or `/usr/local/bin/dcli`:
```bash
curl -LO https://github.com/Dashlane/dashlane-cli/releases/latest/download/dcli-linux-x64
chmod +x dcli-linux-x64
mv dcli-linux-x64 ~/.local/bin/dcli
```

### Initial Login / Sync

To link your Dashlane account for the first time:
```bash
dcli sync
```
You can also click **"Log in via Terminal"** directly within the Omarchy panel, which opens an interactive terminal prompt to handle your email, 2FA code, and Master Password.

---

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| <kbd>Enter</kbd> | Copy selected password or submit unlock |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Navigate item list |
| <kbd>Esc</kbd> | Clear search, return from detail view, or close panel |
| <kbd>Tab</kbd> / <kbd>Shift+Tab</kbd> | Switch between panel tabs / bar widgets |
| <kbd>Ctrl</kbd>+<kbd>L</kbd> | Lock vault immediately |
| <kbd>Ctrl</kbd>+<kbd>R</kbd> | Synchronize vault with Dashlane servers |
| Right-click on bar icon | Quick sync vault |

---

## Configuration (`shell.json`)

The plugin can be customized in `~/.config/omarchy/shell.json` under your bar configuration:

```json
{
  "id": "io.github.boeycorp.qs-dashlane-cli",
  "autoLockMinutes": 15,
  "lockOnScreenLock": true,
  "lockOnSuspend": true,
  "clearClipboardSec": 30,
  "autoCopyTotpSec": 3,
  "closeOnCopy": true,
  "suggestOnOpen": true,
  "colorizeIcon": false
}
```

| Setting | Default | Description |
| --- | --- | --- |
| `autoLockMinutes` | `15` | Minutes of user inactivity before auto-locking (0 to disable) |
| `lockOnScreenLock` | `true` | Lock vault immediately when the screen locks |
| `lockOnSuspend` | `true` | Lock vault when machine suspends |
| `clearClipboardSec` | `30` | Seconds before clearing copied password from clipboard |
| `autoCopyTotpSec` | `3` | Seconds after copying password to auto-copy TOTP 2FA code |
| `closeOnCopy` | `true` | Automatically close popout panel on Enter copy |
| `suggestOnOpen` | `true` | Match focused window to vault logins automatically |
| `colorizeIcon` | `false` | Tint status bar icon with current Omarchy theme accent |

---

## Development & Testing

Run unit tests and validate plugin manifest schema:

```bash
npm test
npm run validate
```

Or run the validation script:
```bash
./scripts/validate.sh
```

---

## License

MIT License. Copyright (c) 2026 [BoeyCorp](https://github.com/BoeyCorp).
Inspired by [qs-bitwarden-cli](https://github.com/Elevate08/qs-bitwarden-cli).
Dashlane is a trademark of Dashlane, Inc.
