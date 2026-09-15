#!/usr/bin/env bash
# Start the YT Channel Scraper (creates the venv on first run).
set -e
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip -r requirements.txt
fi
# ./run.sh --lan serves on the local network so a phone can open it, rather than only
# this machine. Off by default: there is no authentication in front of any of this.
if [ "${1:-}" = "--lan" ]; then
  export YTCS_HOST=0.0.0.0
fi
exec .venv/bin/python app.py
