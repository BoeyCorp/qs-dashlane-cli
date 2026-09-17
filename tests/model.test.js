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

  const unlockCmd = Model.unlockCommand("my'secret'pass");
  assert.strictEqual(unlockCmd[0], "bash");
  assert.strictEqual(unlockCmd[1], "-c");
  assert.ok(unlockCmd[2].includes("DASHLANE_MASTER_PASSWORD="));
  assert.ok(unlockCmd[2].includes("dcli password -o json"));
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

test("JSON parsing and normalization", () => {
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
  assert.strictEqual(items.length, 3);

  // Sorting
  assert.strictEqual(items[0].title, "GitHub");
  assert.strictEqual(items[0].type, "login");
  assert.strictEqual(items[0].hasOtp, true);
  assert.strictEqual(items[0].domain, "github.com");

  assert.strictEqual(items[1].title, "Server SSH");
  assert.strictEqual(items[1].type, "note");

  assert.strictEqual(items[2].title, "Stripe Key");
  assert.strictEqual(items[2].type, "secret");
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
  // Test secret: JBSWY3DPEHPK3PXP (standard base32 for "Hello!\xde\xad\xbe\xef")
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

test("Password and Passphrase generation", () => {
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

test("URL normalization and safety", () => {
  assert.deepStrictEqual(Model.normalizeOpenableUrl("github.com"), { ok: true, url: "https://github.com" });
  assert.deepStrictEqual(Model.normalizeOpenableUrl("https://dashlane.com"), { ok: true, url: "https://dashlane.com" });
  assert.strictEqual(Model.normalizeOpenableUrl("javascript:alert(1)").ok, false);
  assert.strictEqual(Model.normalizeOpenableUrl("file:///etc/passwd").ok, false);
});
