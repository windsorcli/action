#!/usr/bin/env node
'use strict';
// Keeps the Azure federated-token file fresh for kubelogin's workloadidentity
// mode. kubelogin reads the file named by AZURE_FEDERATED_TOKEN_FILE and never
// refreshes it, and GitHub's OIDC token expires after about 5 minutes.
//
// Usage: refresh-federated-token.js start
//   Writes a token to the file now, so a failure shows up in this step. Then it
//   starts a detached copy of this script that rewrites the file every
//   FEDERATED_TOKEN_REFRESH_INTERVAL seconds (default 120). A second `start`
//   refreshes the file and starts no second copy. The copy exits after 8 hours.
//
// Required env: AZURE_FEDERATED_TOKEN_FILE, ACTIONS_ID_TOKEN_REQUEST_TOKEN,
// ACTIONS_ID_TOKEN_REQUEST_URL (the job needs `permissions: id-token: write`).
// The script writes a log, which never holds the token, to "<file>.log".
// The loop's process ID is in "<file>.pid".
const fs = require('fs');
const { spawn } = require('child_process');

const AUDIENCE = 'api://AzureADTokenExchange';
const INTERVAL_MS = Number(process.env.FEDERATED_TOKEN_REFRESH_INTERVAL || 120) * 1000;
const MAX_LIFETIME_MS = 8 * 60 * 60 * 1000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function fail(message) {
  console.error(`::error::${message}`);
  process.exit(1);
}

function requiredEnv() {
  const env = {
    file: process.env.AZURE_FEDERATED_TOKEN_FILE,
    requestToken: process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN,
    requestUrl: process.env.ACTIONS_ID_TOKEN_REQUEST_URL,
  };
  const names = {
    file: 'AZURE_FEDERATED_TOKEN_FILE',
    requestToken: 'ACTIONS_ID_TOKEN_REQUEST_TOKEN',
    requestUrl: 'ACTIONS_ID_TOKEN_REQUEST_URL',
  };
  for (const key of Object.keys(env)) {
    if (!env[key]) {
      fail(`${names[key]} is not set. For the GitHub variables, the job needs 'permissions: id-token: write'.`);
    }
  }
  return env;
}

function log(file, message) {
  try {
    fs.appendFileSync(`${file}.log`, `${new Date().toISOString()} ${message}\n`);
  } catch (_) {
    // A log failure must not stop the refresh.
  }
}

async function fetchToken({ requestToken, requestUrl }) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const response = await fetch(`${requestUrl}&audience=${AUDIENCE}`, {
        headers: { Authorization: `bearer ${requestToken}` },
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const { value } = await response.json();
      if (!value) throw new Error('the response has no token');
      return value;
    } catch (error) {
      lastError = error;
      if (attempt < 3) await sleep(1000);
    }
  }
  throw lastError;
}

// Writes to a temp file, then renames it over the target, so kubelogin never
// reads a partial token. Windows can refuse a rename while a reader has the
// target open, so the rename retries.
async function writeToken(file, value) {
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, value, { mode: 0o600 });
  let lastError;
  for (let attempt = 1; attempt <= 10; attempt++) {
    try {
      fs.renameSync(tmp, file);
      return;
    } catch (error) {
      lastError = error;
      await sleep(100);
    }
  }
  fs.rmSync(tmp, { force: true });
  throw lastError;
}

async function refreshOnce(env) {
  const value = await fetchToken(env);
  await writeToken(env.file, value);
  log(env.file, `token written, ${value.length} bytes`);
}

function isAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (_) {
    return false;
  }
}

async function start() {
  const env = requiredEnv();
  try {
    await refreshOnce(env);
  } catch (error) {
    log(env.file, `first token fetch failed: ${error.message}`);
    fail(`Could not fetch a federated token from GitHub's OIDC endpoint (${error.message}). The job needs 'permissions: id-token: write'.`);
  }

  const pidFile = `${env.file}.pid`;
  const existing = Number(fs.existsSync(pidFile) ? fs.readFileSync(pidFile, 'utf8') : 0);
  if (existing && isAlive(existing)) {
    console.log(`The token refresher already runs (process ${existing}). The token is fresh.`);
    return;
  }

  const child = spawn(process.execPath, [__filename, 'loop'], {
    detached: true,
    stdio: 'ignore',
    windowsHide: true,
    env: process.env,
  });
  child.unref();
  fs.writeFileSync(pidFile, String(child.pid));
  console.log(`Started the token refresher (process ${child.pid}). It refreshes ${env.file} every ${INTERVAL_MS / 1000} seconds.`);
}

function loop() {
  const env = requiredEnv();
  log(env.file, `refresher started, interval ${INTERVAL_MS / 1000} seconds`);
  let running = false;
  setInterval(async () => {
    if (running) return;
    running = true;
    try {
      await refreshOnce(env);
    } catch (error) {
      // The old token can still be valid, so keep going and try again.
      log(env.file, `refresh failed: ${error.message}`);
    }
    running = false;
  }, INTERVAL_MS);
  setTimeout(() => process.exit(0), MAX_LIFETIME_MS);
}

const mode = process.argv[2];
if (mode === 'start') {
  start();
} else if (mode === 'loop') {
  loop();
} else {
  fail('usage: refresh-federated-token.js start');
}
