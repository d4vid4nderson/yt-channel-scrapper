#!/usr/bin/env bash
# Start the YT Channel Scraper (creates the venv on first run).
set -e
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip -r requirements.txt
fi
exec .venv/bin/python app.py
