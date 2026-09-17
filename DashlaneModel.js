// DashlaneModel.js - Core logic and data helpers for Dashlane Omarchy plugin
// Inspired by qs-bitwarden-cli and designed for 1st-party Dashlane CLI (dcli).

// ---------------------------------------------------------------------------
// Shell quoting and CLI command builders
// ---------------------------------------------------------------------------

function shellQuote(str) {
  if (typeof str !== "string") str = String(str || "");
  return "'" + str.replace(/'/g, "'\\''") + "'";
}

function checkCliCommand() {
  return ["which", "dcli"];
}

function statusCommand() {
  return ["dcli", "status"];
}

function passwordsCommand() {
  return ["dcli", "password", "-o", "json"];
}

function notesCommand() {
  return ["dcli", "note", "-o", "json"];
}

function secretsCommand() {
  return ["dcli", "secret", "-o", "json"];
}

function unlockCommand() {
  // Invokes dcli directly without intermediate bash wrapper or shell script.
  // The master password is provided directly to the child process via Quickshell's
  // per-process 'environment' property (QProcess::setProcessEnvironment), ensuring
  // that argv and /proc/<pid>/cmdline contain only ["dcli", "password", "-o", "json"].
  return ["dcli", "password", "-o", "json"];
}

function sanitizeUnlockError(rawStderr, exitCode) {
  // Exit code 127 is the POSIX standard signal for command not found.
  // Check this first as it is the most reliable indication that the binary is missing.
  if (exitCode === 127) {
    return "Dashlane CLI (dcli) could not be executed. Please verify your installation.";
  }

  var raw = String(rawStderr || "").trim();
  if (!raw) {
    return "Incorrect master password.";
  }

  var lower = raw.toLowerCase();

  // Missing CLI binary / execution failure from text output
  if (
    lower.includes("command not found") ||
    (lower.includes("no such file or directory") && lower.includes("dcli")) ||
    (lower.includes("enoent") && lower.includes("dcli"))
  ) {
    return "Dashlane CLI (dcli) could not be executed. Please verify your installation.";
  }

  // 1. Password or decryption failures
  if (
    lower.includes("password") ||
    lower.includes("incorrect") ||
    lower.includes("invalid master") ||
    lower.includes("authentication failed") ||
    lower.includes("auth failed") ||
    lower.includes("decrypt") ||
    lower.includes("bad key") ||
    lower.includes("credential")
  ) {
    return "Incorrect master password.";
  }

  // 2. Device registration or unauthenticated sessions
  if (
    lower.includes("device") ||
    lower.includes("not registered") ||
    lower.includes("not logged in") ||
    lower.includes("session expired") ||
    lower.includes("unauthenticated") ||
    lower.includes("unauthorized") ||
    lower.includes("account not found") ||
    lower.includes("user not found")
  ) {
    return "Dashlane session expired or device not registered. Run 'dcli login' in terminal.";
  }

  // 3. Rate limiting or lockouts
  if (
    lower.includes("rate limit") ||
    lower.includes("too many") ||
    lower.includes("throttle") ||
    lower.includes("locked out")
  ) {
    return "Too many failed attempts. Please try again later.";
  }

  // 4. Network / communication issues
  if (
    lower.includes("network") ||
    lower.includes("connect") ||
    lower.includes("econnrefused") ||
    lower.includes("timeout") ||
    lower.includes("fetch failed") ||
    lower.includes("dns") ||
    lower.includes("socket")
  ) {
    return "Network error communicating with Dashlane servers.";
  }

  // Generic fallback: strictly avoid leaking file paths, tracebacks, or raw codes
  return "Failed to unlock vault. Please check your credentials or CLI status.";
}

function lockCommand() {
  return ["dcli", "lock"];
}

function syncCommand() {
  return ["dcli", "sync"];
}

function logoutCommand() {
  return ["dcli", "logout"];
}

function terminalSyncCommand() {
  // Launches terminal for interactive registration/sync/SSO/2FA
  var inner = "echo '=== Dashlane CLI Interactive Sync / Login ==='; "
    + "echo 'If this is your first time, you will be prompted for your email, 2FA, and Master Password.'; "
    + "echo; dcli sync; "
    + "echo; read -p 'Press [Enter] to return to the Omarchy panel...'";
  var script = "omarchy launch floating terminal with presentation " + shellQuote(inner)
    + " || omarchy launch terminal -e bash -c " + shellQuote(inner)
    + " || alacritty -e bash -c " + shellQuote(inner)
    + " || kitty -e bash -c " + shellQuote(inner);
  return ["bash", "-c", script];
}

function terminalInstallCommand() {
  var inner = "echo '=== Installing Dashlane CLI (dcli) ==='; "
    + "if which yay >/dev/null 2>&1; then yay -S --noconfirm dcli-git; "
    + "elif which paru >/dev/null 2>&1; then paru -S --noconfirm dcli-git; "
    + "elif which npm >/dev/null 2>&1; then sudo npm install -g @dashlane/cli; "
    + "else echo 'Neither yay, paru, nor npm found. Please install dcli from https://cli.dashlane.com/install'; fi; "
    + "echo; read -p 'Press [Enter] to close...'";
  var script = "omarchy launch floating terminal with presentation " + shellQuote(inner)
    + " || omarchy launch terminal -e bash -c " + shellQuote(inner);
  return ["bash", "-c", script];
}

function activeWindowCommand() {
  return ["sh", "-c", "hyprctl activewindow -j 2>/dev/null || true"];
}

function screenLockStateCommand() {
  return ["bash", "-c", "omarchy-shell lock isLocked 2>/dev/null | head -c 16"];
}

function screenIsLocked(raw) {
  return String(raw || "").trim() === "true";
}

function sleepMonitorCommand() {
  return ["bash", "-c", "gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 2>/dev/null | grep --line-buffered 'PrepareForSleep (true'"];
}

function copyCommand(text) {
  return ["wl-copy", "--type", "text/plain", "--", String(text || "")];
}

function clearClipboardCommand() {
  // Clears clipboard unconditionally if EXPECTED_SECRET is unset/empty,
  // or clears only if the current clipboard content matches EXPECTED_SECRET.
  // The secret is passed via Process.environment in Service.qml to avoid
  // exposing sensitive data in argv or /proc/<pid>/cmdline.
  return [
    "bash",
    "-c",
    "if [ -z \"$EXPECTED_SECRET\" ] || [ \"$(wl-paste -n 2>/dev/null)\" = \"$EXPECTED_SECRET\" ]; then wl-copy --clear; fi"
  ];
}

function openUrlCommand(url) {
  var safe = normalizeOpenableUrl(url);
  if (!safe.ok) return null;
  return ["xdg-open", safe.url];
}

// ---------------------------------------------------------------------------
// Status Parsing
// ---------------------------------------------------------------------------

function parseStatus(text) {
  var raw = String(text || "");
  var lines = raw.split("\n");
  var loggedIn = false;
  var locked = true;
  var login = "";

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (/^logged in:\s*yes/i.test(line)) {
      loggedIn = true;
    } else if (/^logged in:\s*no/i.test(line)) {
      loggedIn = false;
    }

    var loginMatch = line.match(/^login:\s*(.+)$/i);
    if (loginMatch) {
      login = loginMatch[1].trim();
    }

    if (/^locked:\s*yes/i.test(line)) {
      locked = true;
    } else if (/^locked:\s*no/i.test(line)) {
      locked = false;
    }
  }

  return {
    loggedIn: loggedIn,
    locked: locked,
    login: login,
    raw: raw
  };
}

// ---------------------------------------------------------------------------
// JSON Parsing & Normalization
// ---------------------------------------------------------------------------

var _itemIdCounter = 0;
function _nextFallbackId() {
  _itemIdCounter += 1;
  return "fallback-" + _itemIdCounter;
}

function parseJsonSafely(str, fallback) {
  if (fallback === undefined) fallback = [];
  if (!str || typeof str !== "string") return fallback;
  try {
    return JSON.parse(str);
  } catch (e) {
    return fallback;
  }
}

function extractDomain(url) {
  if (!url || typeof url !== "string") return "";
  var match = url.match(/^(?:https?:\/\/)?(?:[^@\n]+@)?(?:www\.)?([^:\/\n?#]+)/i);
  return match ? match[1].toLowerCase() : "";
}

function normalizeCredential(c) {
  if (!c || typeof c !== "object") return null;
  var title = (c.title && c.title.trim()) ? c.title.trim() : (c.url ? extractDomain(c.url) : "Untitled Login");
  var username = (c.login && c.login.trim()) || (c.email && c.email.trim()) || (c.secondaryLogin && c.secondaryLogin.trim()) || "";
  var hasOtp = Boolean((c.otpSecret && c.otpSecret.trim()) || (c.otpUrl && c.otpUrl.trim()));

  return {
    id: String(c.id || c.anonId || _nextFallbackId()),
    type: "login",
    title: title,
    username: username,
    email: (c.email && c.email.trim()) || "",
    password: c.password || "",
    url: c.url || "",
    domain: extractDomain(c.url),
    hasOtp: hasOtp,
    otpSecret: (c.otpSecret && c.otpSecret.trim()) || "",
    otpUrl: (c.otpUrl && c.otpUrl.trim()) || "",
    category: (c.category && c.category.trim()) || "General",
    note: c.note || "",
    content: "",
    strength: parseInt(c.strength, 10) || 0,
    lastModified: c.modificationDatetime || c.lastBackupTime || ""
  };
}

function normalizeNote(n) {
  if (!n || typeof n !== "object") return null;
  var title = (n.title && n.title.trim()) ? n.title.trim() : "Untitled Note";

  return {
    id: String(n.id || n.anonId || _nextFallbackId()),
    type: "note",
    title: title,
    username: "",
    email: "",
    password: "",
    url: "",
    domain: "",
    hasOtp: false,
    otpSecret: "",
    otpUrl: "",
    category: (n.category && n.category.trim()) || "Secure Notes",
    note: n.content || "",
    content: n.content || "",
    strength: 0,
    lastModified: n.updateDate || n.userModificationDatetime || n.lastBackupTime || ""
  };
}

function normalizeSecret(s) {
  if (!s || typeof s !== "object") return null;
  var title = (s.title && s.title.trim()) ? s.title.trim() : "Untitled Secret";

  return {
    id: String(s.id || s.anonId || _nextFallbackId()),
    type: "secret",
    title: title,
    username: "",
    email: "",
    password: s.content || "",
    url: "",
    domain: "",
    hasOtp: false,
    otpSecret: "",
    otpUrl: "",
    category: (s.category && s.category.trim()) || "Secrets",
    note: "",
    content: s.content || "",
    strength: 0,
    lastModified: s.updateDate || s.userModificationDatetime || s.lastBackupTime || ""
  };
}

function combineAndSortItems(credentials, notes, secrets) {
  var list = [];
  var i;

  if (Array.isArray(credentials)) {
    for (i = 0; i < credentials.length; i++) {
      var item = normalizeCredential(credentials[i]);
      if (item) list.push(item);
    }
  }

  if (Array.isArray(notes)) {
    for (i = 0; i < notes.length; i++) {
      var noteItem = normalizeNote(notes[i]);
      if (noteItem) list.push(noteItem);
    }
  }

  if (Array.isArray(secrets)) {
    for (i = 0; i < secrets.length; i++) {
      var secItem = normalizeSecret(secrets[i]);
      if (secItem) list.push(secItem);
    }
  }

  list.sort(function(a, b) {
    return a.title.localeCompare(b.title, undefined, { sensitivity: "base" });
  });

  return list;
}

// ---------------------------------------------------------------------------
// Search & Filter
// ---------------------------------------------------------------------------

function filterItems(items, query, activeTab, categoryFilter) {
  if (!Array.isArray(items)) return [];
  var q = (query || "").trim().toLowerCase();
  var tab = (activeTab || "all").toLowerCase();
  var cat = (categoryFilter || "").trim();

  return items.filter(function(item) {
    // 1. Tab filter
    if (tab === "logins" && item.type !== "login") return false;
    if (tab === "notes" && item.type !== "note") return false;
    if (tab === "secrets" && item.type !== "secret") return false;

    // 2. Category filter
    if (cat && cat !== "All" && item.category !== cat) return false;

    // 3. Search query
    if (!q) return true;

    if (item.title && item.title.toLowerCase().indexOf(q) !== -1) return true;
    if (item.username && item.username.toLowerCase().indexOf(q) !== -1) return true;
    if (item.email && item.email.toLowerCase().indexOf(q) !== -1) return true;
    if (item.domain && item.domain.toLowerCase().indexOf(q) !== -1) return true;
    if (item.url && item.url.toLowerCase().indexOf(q) !== -1) return true;
    if (item.category && item.category.toLowerCase().indexOf(q) !== -1) return true;
    if (item.note && item.note.toLowerCase().indexOf(q) !== -1) return true;
    if (item.content && item.content.toLowerCase().indexOf(q) !== -1) return true;

    return false;
  });
}

function getCategories(items) {
  if (!Array.isArray(items)) return [];
  var counts = {};
  for (var i = 0; i < items.length; i++) {
    var c = items[i].category || "General";
    counts[c] = (counts[c] || 0) + 1;
  }
  var list = Object.keys(counts).sort();
  var result = [{ name: "All", count: items.length }];
  for (var j = 0; j < list.length; j++) {
    result.push({ name: list[j], count: counts[list[j]] });
  }
  return result;
}

// ---------------------------------------------------------------------------
// Active Window Matching
// ---------------------------------------------------------------------------

function matchActiveWindow(items, windowJson) {
  if (!Array.isArray(items) || !windowJson) return null;
  var win = (typeof windowJson === "string") ? parseJsonSafely(windowJson, null) : windowJson;
  if (!win) return null;

  var title = String(win.title || "").toLowerCase();
  var winClass = String(win.class || win.initialClass || "").toLowerCase();

  if (!title && !winClass) return null;

  var bestItem = null;
  var bestScore = 0;

  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    if (item.type !== "login") continue;

    var score = 0;
    var domain = (item.domain || "").toLowerCase();
    var itemTitle = (item.title || "").toLowerCase();

    // Domain exact match in window title (e.g. "github.com" in browser title)
    if (domain && domain.length > 3 && title.indexOf(domain) !== -1) {
      score = Math.max(score, 100);
    }

    // Domain root word match (e.g. "github" in "GitHub: Where the world builds...")
    var domainRoot = domain.split(".")[0];
    if (domainRoot && domainRoot.length > 3 && title.indexOf(domainRoot) !== -1) {
      score = Math.max(score, 80);
    }

    // Title match in window title
    if (itemTitle && itemTitle.length > 3 && title.indexOf(itemTitle) !== -1) {
      score = Math.max(score, 70);
    }

    // Item title matches app class (e.g. Discord, Spotify, Slack)
    if (itemTitle && winClass && winClass.indexOf(itemTitle) !== -1) {
      score = Math.max(score, 90);
    }

    if (score > bestScore) {
      bestScore = score;
      bestItem = item;
    }
  }

  return bestScore >= 70 ? bestItem : null;
}

// ---------------------------------------------------------------------------
// URL Normalization & Safety
// ---------------------------------------------------------------------------

var HTTP_URL_RE = /^https?:\/\//i;
var EXPLICIT_SCHEME_RE = /^([a-zA-Z][a-zA-Z0-9+.-]*):(?!\d)/;

function normalizeOpenableUrl(raw) {
  var url = String(raw || "").trim();
  if (!url) return { ok: false, reason: "empty" };

  if (HTTP_URL_RE.test(url)) {
    return { ok: true, url: url };
  }

  // Refuse explicit non-http schemes (e.g. javascript:, file:, ftp:, smb:, ssh:, data:, etc.)
  // A colon followed by digits (e.g. localhost:8080) is a port, not a scheme.
  if (EXPLICIT_SCHEME_RE.test(url)) {
    return { ok: false, reason: "unsafe_scheme" };
  }

  // Bare hostname or host:port — prepend https://
  return { ok: true, url: "https://" + url };
}

// ---------------------------------------------------------------------------
// Pure JS SHA-1 and HMAC Implementation (RFC 3174 & RFC 2104)
// Required for TOTP calculation without external C/native dependencies.
// ---------------------------------------------------------------------------

function sha1(bytes) {
  function rotl(n, s) { return (n << s) | (n >>> (32 - s)); }

  var blocks = [];
  var i, j;
  var byteCount = bytes.length;
  for (i = 0; i < byteCount; i++) {
    blocks[i >> 2] |= (bytes[i] & 0xff) << (24 - (i % 4) * 8);
  }
  blocks[byteCount >> 2] |= 0x80 << (24 - (byteCount % 4) * 8);

  var totalBits = byteCount * 8;
  var wordLength = (((byteCount + 8) >> 6) + 1) * 16;
  while (blocks.length < wordLength) blocks.push(0);
  blocks[wordLength - 1] = totalBits & 0xffffffff;
  blocks[wordLength - 2] = Math.floor(totalBits / 0x100000000);

  var h0 = 0x67452301;
  var h1 = 0xefcdab89;
  var h2 = 0x98badcfe;
  var h3 = 0x10325476;
  var h4 = 0xc3d2e1f0;

  var w = new Array(80);
  for (i = 0; i < blocks.length; i += 16) {
    for (j = 0; j < 16; j++) w[j] = blocks[i + j] | 0;
    for (j = 16; j < 80; j++) w[j] = rotl(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);

    var a = h0, b = h1, c = h2, d = h3, e = h4;
    for (j = 0; j < 80; j++) {
      var f, k;
      if (j < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5a827999;
      } else if (j < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (j < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }
      var temp = (rotl(a, 5) + f + e + k + w[j]) | 0;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) | 0;
    h1 = (h1 + b) | 0;
    h2 = (h2 + c) | 0;
    h3 = (h3 + d) | 0;
    h4 = (h4 + e) | 0;
  }

  var out = [];
  var digests = [h0, h1, h2, h3, h4];
  for (i = 0; i < 5; i++) {
    for (j = 3; j >= 0; j--) {
      out.push((digests[i] >>> (j * 8)) & 0xff);
    }
  }
  return out;
}

function hmacSha1(keyBytes, msgBytes) {
  var blockSize = 64;
  var key = keyBytes.slice();
  if (key.length > blockSize) key = sha1(key);
  while (key.length < blockSize) key.push(0);

  var oKeyPad = new Array(blockSize);
  var iKeyPad = new Array(blockSize);
  for (var i = 0; i < blockSize; i++) {
    oKeyPad[i] = key[i] ^ 0x5c;
    iKeyPad[i] = key[i] ^ 0x36;
  }

  var inner = sha1(iKeyPad.concat(msgBytes));
  return sha1(oKeyPad.concat(inner));
}

// Base32 Decoder (RFC 4648)
function base32Decode(str) {
  var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  var cleaned = String(str || "").toUpperCase().replace(/[\s=-]/g, "");
  var bits = 0;
  var value = 0;
  var output = [];

  for (var i = 0; i < cleaned.length; i++) {
    var idx = alphabet.indexOf(cleaned[i]);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      output.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return output;
}

// ---------------------------------------------------------------------------
// TOTP Generation (RFC 6238)
// ---------------------------------------------------------------------------

function extractTotpSecret(otpSecretOrUrl) {
  var s = String(otpSecretOrUrl || "").trim();
  if (!s) return "";
  if (/^otpauth:\/\/totp\//i.test(s)) {
    var match = s.match(/[?&]secret=([A-Za-z2-7=]+)/i);
    return match ? match[1] : "";
  }
  return s;
}

function generateTotp(otpSecretOrUrl, epochSeconds) {
  var secret = extractTotpSecret(otpSecretOrUrl);
  if (!secret) return null;

  var now = (typeof epochSeconds === "number") ? epochSeconds : Math.floor(Date.now() / 1000);
  var period = 30;
  var counter = Math.floor(now / period);
  var remaining = period - (now % period);

  var keyBytes = base32Decode(secret);
  if (keyBytes.length === 0) return null;

  // Convert 64-bit counter to 8 bytes
  var msgBytes = [0, 0, 0, 0, 0, 0, 0, 0];
  var tmp = counter;
  for (var i = 7; i >= 0; i--) {
    msgBytes[i] = tmp & 0xff;
    tmp = Math.floor(tmp / 256);
  }

  var hash = hmacSha1(keyBytes, msgBytes);
  var offset = hash[hash.length - 1] & 0x0f;
  var binary = ((hash[offset] & 0x7f) << 24)
    | ((hash[offset + 1] & 0xff) << 16)
    | ((hash[offset + 2] & 0xff) << 8)
    | (hash[offset + 3] & 0xff);

  var codeNum = binary % 1000000;
  var codeStr = ("000000" + codeNum).slice(-6);

  return {
    code: codeStr,
    remainingSeconds: remaining,
    progress: remaining / period
  };
}

// ---------------------------------------------------------------------------
// Password & Passphrase Generator (with CSPRNG Entropy Pooling)
// ---------------------------------------------------------------------------

var WORD_LIST = [
  "acorn", "amber", "anchor", "anthem", "apex", "apple", "apron", "arctic", "arrow", "atlas",
  "badge", "ballet", "bamboo", "banner", "barrel", "beacon", "breeze", "bridge", "bronze", "bubble",
  "cabin", "cactus", "canyon", "castle", "cedar", "cipher", "citrus", "clover", "cobalt", "comet",
  "copper", "coral", "cosmos", "crater", "crystal", "dagger", "dawn", "delta", "desert", "dolphin",
  "dragon", "echo", "ember", "falcon", "feather", "fern", "flare", "flint", "forest", "fossil",
  "galaxy", "garden", "garnet", "geyser", "glacier", "granite", "harbor", "haven", "hazel", "helix",
  "horizon", "iceberg", "indigo", "island", "jaguar", "jungle", "karma", "lagoon", "lantern", "legend",
  "lotus", "lumber", "lunar", "magnet", "maple", "marble", "matrix", "meadow", "meteor", "mirage",
  "monarch", "moss", "nebula", "nectar", "nexus", "oasis", "obsidian", "ocean", "onyx", "orbit",
  "orchid", "origami", "ozone", "palace", "panther", "pebble", "phoenix", "pillar", "planet", "plasma",
  "polar", "prism", "pulsar", "quartz", "radar", "rainbow", "raven", "reef", "relic", "ripple",
  "river", "rover", "ruby", "safari", "sapphire", "saturn", "scale", "sequoia", "shadow", "shrine",
  "sierra", "signal", "silver", "solace", "solar", "spark", "sphere", "spiral", "spring", "stellar",
  "summit", "sunset", "surge", "talon", "temple", "timber", "titan", "topaz", "torrent", "tower",
  "trail", "tropic", "tulip", "tunnel", "valley", "vapor", "velvet", "vortex", "voyage", "walnut",
  "wander", "willow", "zenith", "zephyr"
];

// In Quickshell/Qt QML, window.crypto and crypto.getRandomValues are not present
// in the V4 JS engine. To deliver cryptographically secure random numbers without
// falling back to predictable Math.random(), Service.qml feeds hardware random
// bytes directly from /dev/urandom into _entropyPool.
var _entropyPool = [];

function feedEntropy(uint32Array) {
  if (Array.isArray(uint32Array)) {
    for (var i = 0; i < uint32Array.length; i++) {
      _entropyPool.push(uint32Array[i] >>> 0);
    }
  }
}

function entropyPoolSize() {
  return _entropyPool.length;
}

function getRandomInt(max) {
  if (max <= 1) return 0;

  // 1. Browser / Web environment with Web Crypto API
  if (typeof crypto !== "undefined" && crypto.getRandomValues) {
    var limit = 0x100000000 - (0x100000000 % max);
    var buf = new Uint32Array(1);
    do {
      crypto.getRandomValues(buf);
    } while (buf[0] >= limit);
    return buf[0] % max;
  }

  // 2. Node.js environment (for unit testing)
  if (typeof require !== "undefined") {
    try {
      var nodeCrypto = require("crypto");
      var limitNode = 0x100000000 - (0x100000000 % max);
      var val;
      do {
        val = nodeCrypto.randomBytes(4).readUInt32BE(0);
      } while (val >= limitNode);
      return val % max;
    } catch (_e) {}
  }

  // 3. Quickshell environment with /dev/urandom entropy pool
  if (_entropyPool.length > 0) {
    var limitPool = 0x100000000 - (0x100000000 % max);
    while (_entropyPool.length > 0) {
      var poolVal = _entropyPool.pop();
      if (poolVal < limitPool) {
        return poolVal % max;
      }
    }
  }

  // 4. Fallback (if entropy pool is depleted before replenishment finishes)
  return Math.floor(Math.random() * max);
}

function generatePassword(opts) {
  opts = opts || {};
  var length = Math.max(8, Math.min(64, opts.length || 20));
  var useUpper = opts.uppercase !== false;
  var useLower = opts.lowercase !== false;
  var useNumbers = opts.numbers !== false;
  var useSymbols = opts.symbols !== false;
  var avoidAmbiguous = opts.excludeAmbiguous === true;

  var upperChars = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  var lowerChars = "abcdefghijkmnopqrstuvwxyz";
  var numberChars = "23456789";
  var symbolChars = "!@#$%^&*()-_=+[]{}|;:,.<>?";

  if (!avoidAmbiguous) {
    upperChars += "IO";
    lowerChars += "l";
    numberChars += "01";
  }

  var charPool = "";
  var guaranteed = [];

  if (useUpper) {
    charPool += upperChars;
    guaranteed.push(upperChars[getRandomInt(upperChars.length)]);
  }
  if (useLower) {
    charPool += lowerChars;
    guaranteed.push(lowerChars[getRandomInt(lowerChars.length)]);
  }
  if (useNumbers) {
    charPool += numberChars;
    guaranteed.push(numberChars[getRandomInt(numberChars.length)]);
  }
  if (useSymbols) {
    charPool += symbolChars;
    guaranteed.push(symbolChars[getRandomInt(symbolChars.length)]);
  }

  if (!charPool) charPool = lowerChars + numberChars;

  var result = guaranteed.slice();
  while (result.length < length) {
    result.push(charPool[getRandomInt(charPool.length)]);
  }

  // Shuffle array using Fisher-Yates
  for (var i = result.length - 1; i > 0; i--) {
    var j = getRandomInt(i + 1);
    var temp = result[i];
    result[i] = result[j];
    result[j] = temp;
  }

  return result.join("");
}

function generatePassphrase(opts) {
  opts = opts || {};
  var wordCount = Math.max(3, Math.min(8, opts.wordCount || 4));
  var separator = (opts.separator !== undefined) ? opts.separator : "-";
  var capitalize = opts.capitalize !== false;

  var chosen = [];
  for (var i = 0; i < wordCount; i++) {
    var w = WORD_LIST[getRandomInt(WORD_LIST.length)];
    if (capitalize) {
      w = w.charAt(0).toUpperCase() + w.slice(1);
    }
    chosen.push(w);
  }

  return chosen.join(separator);
}

function calculateStrength(password) {
  var p = String(password || "");
  if (!p) return { score: 0, label: "Empty", percent: 0 };

  var score = 0;
  if (p.length >= 8) score += 20;
  if (p.length >= 14) score += 20;
  if (p.length >= 20) score += 20;
  if (/[a-z]/.test(p) && /[A-Z]/.test(p)) score += 15;
  if (/[0-9]/.test(p)) score += 10;
  if (/[^a-zA-Z0-9]/.test(p)) score += 15;

  score = Math.min(100, Math.max(0, score));

  var label = "Weak";
  if (score >= 80) label = "Strong";
  else if (score >= 60) label = "Good";
  else if (score >= 40) label = "Fair";

  return {
    score: score,
    percent: score / 100,
    label: label
  };
}

// ---------------------------------------------------------------------------
// Exports for Node.js test environment & QML import
// ---------------------------------------------------------------------------

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    shellQuote: shellQuote,
    checkCliCommand: checkCliCommand,
    statusCommand: statusCommand,
    passwordsCommand: passwordsCommand,
    notesCommand: notesCommand,
    secretsCommand: secretsCommand,
    unlockCommand: unlockCommand,
    sanitizeUnlockError: sanitizeUnlockError,
    lockCommand: lockCommand,
    syncCommand: syncCommand,
    logoutCommand: logoutCommand,
    terminalSyncCommand: terminalSyncCommand,
    terminalInstallCommand: terminalInstallCommand,
    activeWindowCommand: activeWindowCommand,
    screenLockStateCommand: screenLockStateCommand,
    screenIsLocked: screenIsLocked,
    sleepMonitorCommand: sleepMonitorCommand,
    copyCommand: copyCommand,
    clearClipboardCommand: clearClipboardCommand,
    openUrlCommand: openUrlCommand,
    parseStatus: parseStatus,
    parseJsonSafely: parseJsonSafely,
    extractDomain: extractDomain,
    normalizeCredential: normalizeCredential,
    normalizeNote: normalizeNote,
    normalizeSecret: normalizeSecret,
    combineAndSortItems: combineAndSortItems,
    filterItems: filterItems,
    getCategories: getCategories,
    matchActiveWindow: matchActiveWindow,
    normalizeOpenableUrl: normalizeOpenableUrl,
    sha1: sha1,
    hmacSha1: hmacSha1,
    base32Decode: base32Decode,
    extractTotpSecret: extractTotpSecret,
    generateTotp: generateTotp,
    generatePassword: generatePassword,
    generatePassphrase: generatePassphrase,
    calculateStrength: calculateStrength,
    getRandomInt: getRandomInt,
    feedEntropy: feedEntropy,
    entropyPoolSize: entropyPoolSize,
    _nextFallbackId: _nextFallbackId
  };
}
