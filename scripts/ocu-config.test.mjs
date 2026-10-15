import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, readFileSync, writeFileSync, statSync, lstatSync, cpSync, mkdirSync, symlinkSync, readlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { configCommand, configPath, inspectConfig } from "./ocu-config.mjs";

function fixture(t) {
  const directory = mkdtempSync(path.join(tmpdir(), "ocu-config-test-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return { HOME: directory, OPEN_COMPUTER_USE_CONFIG_FILE: path.join(directory, "config.json") };
}

test("config paths and read-only defaults", t => {
  const env = fixture(t);
  assert.equal(configPath({ HOME: "/users/test" }), "/users/test/.config/ocu/config.json");
  assert.equal(configPath({ XDG_CONFIG_HOME: "/settings" }), "/settings/ocu/config.json");
  assert.throws(() => configPath({ XDG_CONFIG_HOME: "relative" }), /absolute/);
  assert.throws(() => configPath({ OPEN_COMPUTER_USE_CONFIG_FILE: "relative.json" }), /absolute/);
  assert.equal(inspectConfig(env).values["image.format"], "png");
  assert.throws(() => statSync(env.OPEN_COMPUTER_USE_CONFIG_FILE), /ENOENT/);
});

test("persistent settings, environment precedence and reset", t => {
  const env = fixture(t);
  configCommand(["set", "image.format", "jpg"], env);
  configCommand(["set", "image.maxLongEdgePixels", "640"], env);
  assert.equal(inspectConfig(env).values["image.format"], "jpg");
  const report = inspectConfig({ ...env, OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION: "800" });
  assert.equal(report.values["image.maxLongEdgePixels"], 800);
  assert.equal(report.sources["image.maxLongEdgePixels"], "env");
  assert.equal(inspectConfig({ ...env, OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION: "NaN" }).values["image.maxLongEdgePixels"], 640);
  configCommand(["reset", "image.format"], env);
  assert.equal(inspectConfig(env).values["image.format"], "png");
  assert.equal(statSync(env.OPEN_COMPUTER_USE_CONFIG_FILE).mode & 0o777, 0o600);
});

test("jpeg is an alias for jpg and webp is not offered", t => {
  const env = fixture(t);
  configCommand(["set", "image.format", "jpeg"], env);
  assert.equal(inspectConfig(env).values["image.format"], "jpg");
  assert.throws(() => configCommand(["set", "image.format", "webp"], env), /png or jpg/);
  assert.equal(inspectConfig({ ...env, OPEN_COMPUTER_USE_IMAGE_FORMAT: "webp" }).values["image.format"], "jpg");
});

test("invalid settings and malformed files never overwrite existing content", t => {
  const env = fixture(t);
  configCommand(["set", "image.format", "jpg"], env);
  const before = readFileSync(env.OPEN_COMPUTER_USE_CONFIG_FILE, "utf8");
  for (const [key, value] of [
    ["image.maxLongEdgePixels", "0"],
    ["image.maxLongEdgePixels", "16385"],
    ["image.maxLongEdgePixels", "1.5"],
    ["image.jpegQuality", "1.2"],
    ["image.captureTimeout", "0"],
    ["image.format", "gif"],
    ["image.discardBelowPixelCount", "-1"],
    ["safety.global", "1"],
    ["allowLocked", "true"],
  ]) {
    assert.throws(() => configCommand(["set", key, value], env), undefined, `${key}=${value}`);
  }
  assert.equal(readFileSync(env.OPEN_COMPUTER_USE_CONFIG_FILE, "utf8"), before);
  writeFileSync(env.OPEN_COMPUTER_USE_CONFIG_FILE, "broken");
  assert.throws(() => configCommand(["set", "image.format", "png"], env), /Cannot read config/);
  assert.equal(readFileSync(env.OPEN_COMPUTER_USE_CONFIG_FILE, "utf8"), "broken");
});

test("a config path that is not a regular file is refused", t => {
  const env = fixture(t);
  env.OPEN_COMPUTER_USE_CONFIG_FILE = env.HOME;
  assert.throws(() => inspectConfig(env), /not a regular file/);
  assert.throws(() => configCommand(["set", "image.format", "jpg"], env), /not a regular file/);
});

test("an oversized config file is refused", t => {
  const env = fixture(t);
  writeFileSync(env.OPEN_COMPUTER_USE_CONFIG_FILE, JSON.stringify({ image: { format: "jpg" }, padding: "x".repeat(70 * 1024) }));
  assert.throws(() => inspectConfig(env), /larger than/);
});

test("invalid persisted values fall back to defaults with a warning", t => {
  const env = fixture(t);
  writeFileSync(env.OPEN_COMPUTER_USE_CONFIG_FILE, JSON.stringify({ image: { format: "webp", jpegQuality: 7, maxLongEdgePixels: "wide" } }));
  const report = inspectConfig(env);
  assert.equal(report.values["image.format"], "png");
  assert.equal(report.values["image.jpegQuality"], 0.8);
  assert.equal(report.values["image.maxLongEdgePixels"], 1280);
  assert.equal(report.warnings.length, 3);
});

test("unknown config fields are preserved on writes", t => {
  const env = fixture(t);
  writeFileSync(env.OPEN_COMPUTER_USE_CONFIG_FILE, JSON.stringify({ future: { enabled: true }, image: { future: "keep" } }));
  configCommand(["set", "image.format", "jpg"], env);
  const saved = JSON.parse(readFileSync(env.OPEN_COMPUTER_USE_CONFIG_FILE));
  assert.equal(saved.future.enabled, true);
  assert.equal(saved.image.future, "keep");
});

test("explicit resize/drop settings, pixel-count threshold and nullable limits", t => {
  const env = fixture(t);
  configCommand(["set", "image.scaleDownAfterMaxSize", "false"], env);
  configCommand(["set", "image.discardBelowPixelCount", "4096"], env);
  configCommand(["set", "image.maxLongEdgePixels", "null"], env);
  const values = inspectConfig(env).values;
  assert.equal(values["image.scaleDownAfterMaxSize"], false);
  assert.equal(values["image.discardBelowPixelCount"], 4096);
  assert.equal(values["image.maxLongEdgePixels"], null);
  assert.throws(() => configCommand(["set", "image.scaleDownAfterMaxSize", "yes"], env), /true or false/);
  assert.throws(() => configCommand(["set", "image.captureTimeout", "null"], env));
});

test("capture timeout is capped at 30 seconds", t => {
  const env = fixture(t);
  configCommand(["set", "image.captureTimeout", "30"], env);
  assert.equal(inspectConfig(env).values["image.captureTimeout"], 30);
  assert.throws(() => configCommand(["set", "image.captureTimeout", "31"], env), /between 0.01 and 30/);
  assert.equal(inspectConfig({ ...env, OPEN_COMPUTER_USE_IMAGE_CAPTURE_TIMEOUT: "300" }).values["image.captureTimeout"], 30);
});

test("a symlinked config is written through and the link survives", t => {
  const env = fixture(t);
  const target = path.join(env.HOME, "dotfiles", "ocu-config.json");
  mkdirSync(path.dirname(target));
  writeFileSync(target, JSON.stringify({ image: { format: "jpg" }, future: "keep" }));
  symlinkSync(target, env.OPEN_COMPUTER_USE_CONFIG_FILE);
  configCommand(["set", "image.maxLongEdgePixels", "640"], env);
  assert.ok(lstatSync(env.OPEN_COMPUTER_USE_CONFIG_FILE).isSymbolicLink());
  assert.equal(readlinkSync(env.OPEN_COMPUTER_USE_CONFIG_FILE), target);
  const saved = JSON.parse(readFileSync(target, "utf8"));
  assert.equal(saved.image.maxLongEdgePixels, 640);
  assert.equal(saved.image.format, "jpg");
  assert.equal(saved.future, "keep");
});

test("a dangling symlinked config is created at its target", t => {
  const env = fixture(t);
  const target = path.join(env.HOME, "dotfiles", "later.json");
  mkdirSync(path.dirname(target));
  symlinkSync(target, env.OPEN_COMPUTER_USE_CONFIG_FILE);
  configCommand(["set", "image.format", "jpg"], env);
  assert.ok(lstatSync(env.OPEN_COMPUTER_USE_CONFIG_FILE).isSymbolicLink());
  assert.equal(JSON.parse(readFileSync(target, "utf8")).image.format, "jpg");
});

test("staged npm launcher persists config without starting a native runtime", t => {
  const env = fixture(t);
  const root = path.join(env.HOME, "repo");
  const source = fileURLToPath(new URL("../", import.meta.url));
  mkdirSync(root);
  for (const entry of ["scripts", "plugins", ".agents", "LICENSE"]) cpSync(path.join(source, entry), path.join(root, entry), { recursive: true });
  // Packaging fixtures only: config must never execute these native artifacts.
  for (const relative of ["Open Computer Use.app/Contents/MacOS/OpenComputerUse", "linux/arm64/open-computer-use", "linux/amd64/open-computer-use", "windows/arm64/open-computer-use.exe", "windows/amd64/open-computer-use.exe"]) {
    const file = path.join(root, "dist", relative);
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, "#!/bin/sh\nexit 97\n", { mode: 0o755 });
  }
  const build = spawnSync(process.execPath, [path.join(root, "scripts/npm/build-packages.mjs"), "--skip-build", "--package", "@vietairs/open-computer-use"], { encoding: "utf8" });
  assert.equal(build.status, 0, build.stderr);
  const launcher = path.join(root, "dist/npm/vietairs-open-computer-use/bin/open-computer-use");
  const runLauncher = args => spawnSync(process.execPath, [launcher, ...args], { env: { ...process.env, ...env }, encoding: "utf8" });

  const set = runLauncher(["config", "set", "image.format", "jpg"]);
  assert.equal(set.status, 0, set.stderr);
  assert.equal(inspectConfig(env).values["image.format"], "jpg");

  const list = runLauncher(["config", "list", "--json"]);
  assert.equal(list.status, 0, list.stderr);
  assert.equal(JSON.parse(list.stdout).values["image.format"], "jpg");

  const help = runLauncher(["help", "config"]);
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /Usage: ocu config/);

  const bad = runLauncher(["config", "set", "image.format", "gif"]);
  assert.equal(bad.status, 1);
  assert.match(bad.stderr, /png or jpg/);
});
