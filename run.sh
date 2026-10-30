#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GAME_ENGINE="${GODOT_BIN:-}"
if [[ -z "$GAME_ENGINE" ]]; then
  if command -v godot >/dev/null 2>&1; then GAME_ENGINE="$(command -v godot)"
  elif command -v godot4 >/dev/null 2>&1; then GAME_ENGINE="$(command -v godot4)"
  elif [[ -x "$PROJECT_DIR/../../work/runtime/Godot_v4.7.2-stable_linux.x86_64" ]]; then GAME_ENGINE="$PROJECT_DIR/../../work/runtime/Godot_v4.7.2-stable_linux.x86_64"
  else
    echo "Install Godot 4.7.2, or run: GODOT_BIN=/path/to/godot ./run.sh" >&2
    exit 1
  fi
fi
exec "$GAME_ENGINE" --path "$PROJECT_DIR" "$@"
