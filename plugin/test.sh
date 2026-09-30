#!/usr/bin/env sh
# Ejecuta los tests busted del plugin en Docker (Lua 5.1).
# Primera vez:  docker build -f Dockerfile.test -t kodash-busted .
cd "$(dirname "$0")"
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd)/dashboardscreensaver.koplugin:/plugin" kodash-busted busted "$@"
