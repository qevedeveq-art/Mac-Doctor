#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
EXPECTED='0ccff60b7bf67bcb9e09cc8f804656a1cafa7eeae7297ee83d10e460ead7d43d'
URL='https://github.com/vladkens/macmon/releases/download/v0.10.0/macmon-v0.10.0.tar.gz'
mkdir -p "$BUILD/macmon"
TMP="$(mktemp -d "$BUILD/macmon-download.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
curl --fail --location --silent --show-error "$URL" --output "$TMP/archive.tar.gz"
ACTUAL="$(shasum -a 256 "$TMP/archive.tar.gz" | awk '{print $1}')"
[[ "$ACTUAL" == "$EXPECTED" ]] || { printf '%s\n' 'Empreinte macmon incorrecte.' >&2; exit 1; }
tar -xzf "$TMP/archive.tar.gz" -C "$TMP" macmon
[[ -f "$TMP/macmon" && ! -L "$TMP/macmon" ]] || { printf '%s\n' 'Archive macmon invalide.' >&2; exit 1; }
install -m 755 "$TMP/macmon" "$BUILD/macmon/macmon"
printf '%s\n' 'macmon 0.10.0 vérifié et prêt pour la compilation.'
