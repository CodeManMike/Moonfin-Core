#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIBLING_PLUGIN_TARGET="$REPO_ROOT/../Plugin/frontend"

print_help() {
  cat <<'EOF'
Usage:
  ./build-web-plugin.sh [TARGET_PLUGIN_FRONTEND_DIR]

Environment:
  FLUTTER_BIN                    Optional absolute path to flutter executable
  MOONFIN_PLUGIN_FRONTEND_DIR    Optional default target dir when arg is omitted

Notes:
  - This script builds Flutter web with base-href /Moonfin/Web/
  - It syncs build/web -> TARGET_PLUGIN_FRONTEND_DIR
  - config.json is excluded because the Plugin serves /Moonfin/Web/config.json dynamically
  - theme/ is protected from build/web delete-sync and synced from web/theme
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  print_help
  exit 0
fi

TARGET_DIR="${1:-${MOONFIN_PLUGIN_FRONTEND_DIR:-}}"
if [ -z "$TARGET_DIR" ]; then
  if [ -d "$SIBLING_PLUGIN_TARGET" ] || [ -f "$SIBLING_PLUGIN_TARGET/.gitkeep" ]; then
    TARGET_DIR="$SIBLING_PLUGIN_TARGET"
  else
    echo "Error: target plugin frontend directory is required when Plugin repo is not a sibling checkout." >&2
    echo "Provide it as: ./build-web-plugin.sh /absolute/path/to/Plugin/frontend" >&2
    echo "Or set MOONFIN_PLUGIN_FRONTEND_DIR." >&2
    exit 1
  fi
fi

resolve_flutter() {
  if [ -n "${FLUTTER_BIN:-}" ] && [ -x "$FLUTTER_BIN" ]; then
    printf '%s\n' "$FLUTTER_BIN"
    return 0
  fi

  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi

  local candidates=(
    "$HOME/flutter/bin/flutter"
    "$HOME/Documents/flutter/bin/flutter"
    "$HOME/snap/flutter/common/flutter/bin/flutter"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Error: Flutter not found. Add flutter to PATH or set FLUTTER_BIN to the full flutter executable path." >&2
  exit 1
}

FLUTTER="$(resolve_flutter)"

echo "Building Flutter web bundle for Moonfin plugin mode..."
"$FLUTTER" build web --wasm --release --base-href "/Moonfin/Web/"

mkdir -p "$TARGET_DIR"
rsync -a --delete --exclude config.json --exclude theme/ "$REPO_ROOT/build/web/" "$TARGET_DIR/"

# Keep Theme Editor assets outside Flutter's build/web output so rsync --delete
# cannot wipe them from the plugin frontend during sync.
if [ -d "$REPO_ROOT/web/theme" ]; then
  mkdir -p "$TARGET_DIR/theme"
  rsync -a --delete "$REPO_ROOT/web/theme/" "$TARGET_DIR/theme/"
else
  echo "Warning: web/theme not found. Existing theme assets in target were preserved."
fi

echo "Synced build/web -> $TARGET_DIR"
echo "config.json is excluded because Plugin serves /Moonfin/Web/config.json dynamically."
