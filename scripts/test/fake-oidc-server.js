#!/usr/bin/env node
'use strict';
// A stand-in for GitHub's OIDC endpoint, for tests. It needs no network.
//
// Usage: fake-oidc-server.js start <dir>
//   Starts a detached server and returns when it listens. The server writes
//   its port to <dir>/port and its process ID to <dir>/server.pid.
//
// Each request must send "Authorization: bearer req-token" and an `audience`
// query parameter. The reply is {"value": "token-N"} with N rising by one
// per request. While the file <dir>/fail exists, every request gets HTTP 500.
const fs = require('fs');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');

const [mode, dir] = process.argv.slice(2);
if (!dir) {
  console.error('usage: fake-oidc-server.js start <dir>');
  process.exit(1);
}

if (mode === 'start') {
  fs.mkdirSync(dir, { recursive: true });
  fs.rmSync(path.join(dir, 'port'), { force: true });
  const child = spawn(process.execPath, [__filename, 'serve', dir], {
    detached: true,
    stdio: 'ignore',
    windowsHide: true,
  });
  child.unref();
  fs.writeFileSync(path.join(dir, 'server.pid'), String(child.pid));
  const deadline = Date.now() + 10000;
  const wait = () => {
    if (fs.existsSync(path.join(dir, 'port'))) return;
    if (Date.now() > deadline) {
      console.error('the fake OIDC server did not start');
      process.exit(1);
    }
    setTimeout(wait, 100);
  };
  wait();
} else if (mode === 'serve') {
  let counter = 0;
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (fs.existsSync(path.join(dir, 'fail'))) {
      res.writeHead(500).end('forced failure');
    } else if (req.headers.authorization !== 'bearer req-token') {
      res.writeHead(401).end('bad authorization header');
    } else if (url.searchParams.get('audience') !== 'api://AzureADTokenExchange') {
      res.writeHead(400).end('bad audience');
    } else {
      counter += 1;
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ value: `token-${counter}` }));
    }
  });
  server.listen(0, '127.0.0.1', () => {
    fs.writeFileSync(path.join(dir, 'port'), String(server.address().port));
  });
}
