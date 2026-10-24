#!/usr/bin/env bash
# Downloads glualint (https://github.com/FPtje/GLuaFixer) into tools/bin.
set -euo pipefail
VERSION="${GLUALINT_VERSION:-1.30.0}"
DIR="$(cd "$(dirname "$0")" && pwd)/bin"
mkdir -p "$DIR"
case "$(uname -s)" in
    Linux) ASSET="glualint-${VERSION}-x86_64-linux.zip" ;;
    Darwin) ASSET="glualint-${VERSION}-x86_64-macos.zip" ;;
    *) echo "unsupported OS, download glualint manually: https://github.com/FPtje/GLuaFixer/releases" >&2; exit 1 ;;
esac
TMP="$(mktemp -d)"
curl -fsSL -o "$TMP/gl.zip" "https://github.com/FPtje/GLuaFixer/releases/download/${VERSION}/${ASSET}"
unzip -o -q "$TMP/gl.zip" -d "$DIR"
chmod +x "$DIR/glualint"
rm -rf "$TMP"
"$DIR/glualint" --version
