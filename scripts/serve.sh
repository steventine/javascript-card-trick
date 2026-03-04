#!/usr/bin/env bash
# serve.sh — Starts a local HTTP server for testing voice.html
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-8080}"

cd "$REPO_ROOT"

if command -v python3 >/dev/null 2>&1; then
  echo "Serving at http://localhost:$PORT/voice.html"
  python3 -m http.server "$PORT"
elif command -v node >/dev/null 2>&1; then
  echo "Serving at http://localhost:$PORT/voice.html"
  node -e "
    const http = require('http');
    const fs = require('fs');
    const path = require('path');
    const root = process.argv[1];
    http.createServer((req, res) => {
      const file = path.join(root, req.url === '/' ? '/index.html' : req.url);
      fs.readFile(file, (err, data) => {
        if (err) { res.writeHead(404); res.end('Not found'); return; }
        const ext = path.extname(file);
        const types = { '.html':'text/html', '.js':'text/javascript', '.css':'text/css' };
        res.writeHead(200, { 'Content-Type': types[ext] || 'application/octet-stream' });
        res.end(data);
      });
    }).listen($PORT);
  " "$REPO_ROOT"
else
  echo "Error: python3 or node required" >&2
  exit 1
fi
