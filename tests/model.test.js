const test = require("node:test");
const assert = require("node:assert");
const Model = require("../DashlaneModel.js");

test("CLI command generation", () => {
  assert.deepStrictEqual(Model.checkCliCommand(), ["which", "dcli"]);
  assert.deepStrictEqual(Model.statusCommand(), ["dcli", "status"]);
  assert.deepStrictEqual(Model.passwordsCommand(), ["dcli", "password", "-o", "json"]);
  assert.deepStrictEqual(Model.notesCommand(), ["dcli", "note", "-o", "json"]);
  assert.deepStrictEqual(Model.secretsCommand(), ["dcli", "secret", "-o", "json"]);
  assert.deepStrictEqual(Model.lockCommand(), ["dcli", "lock"]);
  assert.deepStrictEqual(Model.syncCommand(), ["dcli", "sync"]);
  assert.deepStrictEqual(Model.logoutCommand(), ["dcli", "logout"]);

  // unlockCommand executes dcli directly without shell wrappers or argv leakage
  const unlockCmd = Model.unlockCommand();
  assert.deepStrictEqual(unlockCmd, ["dcli", "password", "-o", "json"]);

  // Lock and sleep monitor commands
  assert.deepStrictEqual(Model.screenLockStateCommand(), ["bash", "-c", "omarchy-shell lock isLocked 2>/dev/null | head -c 16"]);
  assert.strictEqual(Model.screenIsLocked("true\n"), true);
  assert.strictEqual(Model.screenIsLocked("false\n"), false);
  assert.ok(Model.sleepMonitorCommand()[2].includes("gdbus monitor"));

  // Clipboard clear commands
  assert.deepStrictEqual(Model.clearClipboardCommand(), ["wl-copy", "--clear"]);
  const targetedClear = Model.clearClipboardCommand("secret_to_wipe");
  assert.strictEqual(targetedClear[0], "bash");
  assert.ok(targetedClear[2].includes("wl-paste"));
  assert.strictEqual(targetedClear[4], "secret_to_wipe");
});

test("parseStatus handles different outputs", () => {
  const lockedOutput = `
Logged in: yes
Login: boey@example.com
Locked: yes
`;
  const parsed1 = Model.parseStatus(lockedOutput);
  assert.strictEqual(parsed1.loggedIn, true);
  assert.strictEqual(parsed1.locked, true);
  assert.strictEqual(parsed1.login, "boey@example.com");

  const unlockedOutput = `
Logged in: yes
Login: boey@example.com
Locked: no
`;
  const parsed2 = Model.parseStatus(unlockedOutput);
  assert.strictEqual(parsed2.loggedIn, true);
  assert.strictEqual(parsed2.locked, false);
  assert.strictEqual(parsed2.login, "boey@example.com");

  const loggedOutOutput = `
Logged in: no
`;
  const parsed3 = Model.parseStatus(loggedOutOutput);
  assert.strictEqual(parsed3.loggedIn, false);
  assert.strictEqual(parsed3.locked, true);
});

test("JSON parsing and normalization with collision-free fallback IDs", () => {
  const credentials = [
    {
      id: "cred-1",
      title: "GitHub",
      url: "https://github.com/login",
      login: "boey",
      email: "boey@example.com",
      password: "pass123",
      otpSecret: "JBSWY3DPEHPK3PXP",
      category: "Development",
      note: "API token in note",
      strength: "85"
    },
    // Item with missing ID to test fallback ID counter
    {
      title: "NoId Login",
      password: "pwd"
    }
  ];

  const notes = [
    {
      id: "note-1",
      title: "Server SSH",
      content: "ssh-ed25519 AAAAC3...",
      category: "Infrastructure"
    }
  ];

  const secrets = [
    {
      id: "sec-1",
      title: "Stripe Key",
      content: "sk_live_12345",
      category: "Payments"
    }
  ];

  const items = Model.combineAndSortItems(credentials, notes, secrets);
  assert.strictEqual(items.length, 4);

  // Sorting and normalization
  assert.strictEqual(items[0].title, "GitHub");
  assert.strictEqual(items[0].type, "login");
  assert.strictEqual(items[0].hasOtp, true);
  assert.strictEqual(items[0].domain, "github.com");

  const noIdItem = items.find(i => i.title === "NoId Login");
  assert.ok(noIdItem);
  assert.ok(noIdItem.id.startsWith("fallback-"));
});

test("filterItems search & categories", () => {
  const items = [
    { type: "login", title: "GitHub", username: "boey", category: "Dev", domain: "github.com" },
    { type: "login", title: "GitLab", username: "boey", category: "Dev", domain: "gitlab.com" },
    { type: "note", title: "My Notes", category: "Personal", note: "Secret recipe" },
    { type: "secret", title: "AWS Key", category: "Cloud", content: "AKIA123456" }
  ];

  // Tab filters
  assert.strictEqual(Model.filterItems(items, "", "logins").length, 2);
  assert.strictEqual(Model.filterItems(items, "", "notes").length, 1);
  assert.strictEqual(Model.filterItems(items, "", "secrets").length, 1);
  assert.strictEqual(Model.filterItems(items, "", "all").length, 4);

  // Query filter
  assert.strictEqual(Model.filterItems(items, "git", "all").length, 2);
  assert.strictEqual(Model.filterItems(items, "recipe", "all").length, 1);
  assert.strictEqual(Model.filterItems(items, "AKIA", "all").length, 1);

  // Category filter
  assert.strictEqual(Model.filterItems(items, "", "all", "Dev").length, 2);

  const categories = Model.getCategories(items);
  assert.strictEqual(categories[0].name, "All");
  assert.strictEqual(categories[0].count, 4);
});

test("TOTP generation (RFC 6238)", () => {
  const epoch1 = 1700000000;
  const totp1 = Model.generateTotp("JBSWY3DPEHPK3PXP", epoch1);
  assert.ok(totp1);
  assert.strictEqual(totp1.code.length, 6);
  assert.ok(/^\d{6}$/.test(totp1.code));
  assert.ok(totp1.remainingSeconds >= 1 && totp1.remainingSeconds <= 30);

  // otpauth URL format
  const urlTotp = Model.generateTotp("otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP", epoch1);
  assert.strictEqual(urlTotp.code, totp1.code);
});

test("Password and Passphrase generation with entropy pool", () => {
  // Feed test entropy to pool
  Model.feedEntropy([123456789, 987654321, 555555555, 111111111, 222222222, 333333333]);
  assert.ok(Model.entropyPoolSize() > 0);

  const pwd = Model.generatePassword({ length: 24, symbols: true });
  assert.strictEqual(pwd.length, 24);
  const strength = Model.calculateStrength(pwd);
  assert.strictEqual(strength.label, "Strong");
  assert.ok(strength.score >= 80);

  const pass = Model.generatePassphrase({ wordCount: 4, separator: "-" });
  const words = pass.split("-");
  assert.strictEqual(words.length, 4);
});

test("Active window matching", () => {
  const items = [
    { type: "login", title: "GitHub", domain: "github.com", username: "boey" },
    { type: "login", title: "Google", domain: "google.com", username: "boey" }
  ];

  const windowData = {
    class: "firefox",
    title: "BoeyCorp/omarchy: Beautiful Linux - GitHub - Mozilla Firefox"
  };

  const matched = Model.matchActiveWindow(items, windowData);
  assert.ok(matched);
  assert.strictEqual(matched.title, "GitHub");
});

test("URL normalization, ports, and scheme security", () => {
  assert.deepStrictEqual(Model.normalizeOpenableUrl("github.com"), { ok: true, url: "https://github.com" });
  assert.deepStrictEqual(Model.normalizeOpenableUrl("https://dashlane.com"), { ok: true, url: "https://dashlane.com" });
  assert.deepStrictEqual(Model.normalizeOpenableUrl("http://insecure.site"), { ok: true, url: "http://insecure.site" });
  
  // Host with port should be permitted and prepended with https://
  assert.deepStrictEqual(Model.normalizeOpenableUrl("localhost:8080"), { ok: true, url: "https://localhost:8080" });
  assert.deepStrictEqual(Model.normalizeOpenableUrl("192.168.1.1:3000"), { ok: true, url: "https://192.168.1.1:3000" });
  assert.deepStrictEqual(Model.normalizeOpenableUrl("mydevserver:9000/api"), { ok: true, url: "https://mydevserver:9000/api" });

  // Explicit non-http schemes must be rejected
  assert.strictEqual(Model.normalizeOpenableUrl("javascript:alert(1)").ok, false);
  assert.strictEqual(Model.normalizeOpenableUrl("file:///etc/passwd").ok, false);
  assert.strictEqual(Model.normalizeOpenableUrl("ftp://ftp.example.com").ok, false);
  assert.strictEqual(Model.normalizeOpenableUrl("ssh://user@server").ok, false);
  assert.strictEqual(Model.normalizeOpenableUrl("data:text/html,evil").ok, false);
  assert.strictEqual(Model.normalizeOpenableUrl("smb://nas/share").ok, false);
});

test("Unlock error message sanitization", () => {
  // Authentication failure
  assert.strictEqual(
    Model.sanitizeUnlockError("Error: Invalid master password"),
    "Incorrect master password."
  );
  assert.strictEqual(
    Model.sanitizeUnlockError("decryption failed: bad key"),
    "Incorrect master password."
  );
  assert.strictEqual(
    Model.sanitizeUnlockError(""),
    "Incorrect master password."
  );

  // Device registration / session expiration
  assert.strictEqual(
    Model.sanitizeUnlockError("Device not registered"),
    "Dashlane session expired or device not registered. Run 'dcli login' in terminal."
  );
  assert.strictEqual(
    Model.sanitizeUnlockError("User is unauthorized or unauthenticated"),
    "Dashlane session expired or device not registered. Run 'dcli login' in terminal."
  );

  // Network error
  assert.strictEqual(
    Model.sanitizeUnlockError("fetch failed: ECONNREFUSED"),
    "Network error communicating with Dashlane servers."
  );

  // Rate limiting
  assert.strictEqual(
    Model.sanitizeUnlockError("Rate limit exceeded: too many requests"),
    "Too many failed attempts. Please try again later."
  );

  // Missing CLI binary
  assert.strictEqual(
    Model.sanitizeUnlockError("bash: dcli: command not found", 127),
    "Dashlane CLI (dcli) could not be executed. Please verify your installation."
  );

  // Internal path / stack trace sanitization (prevents leaking filesystem paths or internals)
  const stackTrace = `Error: SQLite error
    at Object.openSync (node:fs:580:18)
    at /home/boey/.config/dashlane/vault.db
    at Session.validate (/usr/lib/node_modules/@dashlane/cli/index.js:12:4)`;
  const sanitized = Model.sanitizeUnlockError(stackTrace);
  assert.strictEqual(sanitized, "Failed to unlock vault. Please check your credentials or CLI status.");
  assert.ok(!sanitized.includes("/home/boey"));
  assert.ok(!sanitized.includes("node:fs"));
  assert.ok(!sanitized.includes("SQLite"));
});

