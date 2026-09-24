#!/usr/bin/env bash
# Rebuilds local toolchains from chunk files committed under toolkits/.
# Produced on the GitHub Actions runner (which has full internet) by
# tool/prepare_gradle_wrapper.sh; reassembled here because this sandbox can
# only move bytes through git.
#
# Usage:  bash toolkits/assemble-toolkit.sh [TOOLKIT_HOME]   (default ~/builder-toolkit)
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$HOME/builder-toolkit}"
MANIFEST="$SRC/MANIFEST"

[ -f "$MANIFEST" ] || { echo "toolkits/MANIFEST missing — CI has not packed the toolkit yet"; exit 1; }

mkdir -p "$DEST"
cd "$SRC"

# 1) verify + reassemble chunked payloads
awk '{print $3}' MANIFEST | sort -u | while read -r whole; do
  parts=("${whole}".part-*)
  [ -e "${parts[0]}" ] || continue
  echo "◇ assembling $whole"
  cat "${whole}".part-* > "$whole"
done

# 2) checksums
echo "◇ verifying checksums"
sha256sum -c <(awk '{print $1 "  " $2}' MANIFEST)

extract_if() { # <archive> <target dir>
  local arc="$1" tgt="$2"
  [ -f "$arc" ] || { echo "— $arc absent, skipped"; return 0; }
  echo "◇ extracting $arc → $tgt"
  mkdir -p "$tgt"
  case "$arc" in
    *.tar.xz) tar -xJf "$arc" -C "$tgt" --strip-components=1 ;;
    *.tar.gz) tar -xzf "$arc" -C "$tgt" --strip-components=1 ;;
    *.zip)    unzip -qo "$arc" -d "$tgt" ;;
  esac
}

# 3) lay out the standard tree
extract_if flutter-sdk.tar.xz            "$DEST/flutter"
extract_if jdk17.tar.xz                  "$DEST/jdk-17"
extract_if android-build-tools.tar.xz    "$DEST/android-sdk/build-tools/34.0.0"
extract_if android-platform-tools.tar.xz "$DEST/android-sdk/platform-tools"
extract_if android-platform-34.tar.xz    "$DEST/android-sdk/platforms/android-34"
extract_if pub-cache.tar.xz              "$DEST/pub-cache"
extract_if gradle-8.3-bin.zip            "$DEST/_gradle_zip"

# Flutter refuses to run outside a git checkout. Restore a shallow clone at the
# revision the packed flutter_tools stamp expects (from bin/cache stamp).
if [ -d "$DEST/flutter" ] && [ ! -d "$DEST/flutter/.git" ]; then
  REV="$(cut -d: -f1 "$DEST/flutter/bin/cache/flutter_tools.stamp" 2>/dev/null || true)"
  if [ -n "$REV" ]; then
    echo "◇ restoring flutter git checkout @ $REV"
    (cd "$DEST/flutter" && git init -q &&
     git remote add origin https://github.com/flutter/flutter &&
     git fetch --depth 1 origin "$REV" && git reset -q FETCH_HEAD) || true
  fi
fi

# pub 3.5.4 crashes the flutter tool when it cannot complete its security-
# advisories lookup (offline environments). Stripping 'advisoriesUpdated' from
# the cached version listings makes pub skip advisories entirely (documented
# early-return in HostedSource._getAdvisories).
if [ -d "$DEST/pub-cache/hosted/pub.dev/.cache" ]; then
  echo "◇ neutralizing pub advisories lookups (offline fix)"
  DEST_CACHE="$DEST/pub-cache/hosted/pub.dev/.cache" python3 - <<'PY' || true
import json, glob, os
def strip(o):
    if isinstance(o, dict):
        o.pop('advisoriesUpdated', None)
        for v in o.values(): strip(v)
    elif isinstance(o, list):
        for v in o: strip(v)
for p in glob.glob(os.environ.get('DEST_CACHE', '') + '/*-versions.json'):
    doc = json.load(open(p)); strip(doc); json.dump(doc, open(p, 'w'))
for p in glob.glob(os.environ.get('DEST_CACHE', '') + '/*-advisories.json'):
    os.remove(p)
PY
fi

if [ -d "$DEST/_gradle_zip/gradle-8.3" ]; then
  mv "$DEST/_gradle_zip/gradle-8.3" "$DEST/gradle-8.3"
  rm -rf "$DEST/_gradle_zip"
fi

echo
echo "assembled into $DEST — now run:  source $(dirname "$0")/../toolkit/env.sh  (or /home/user/toolkit/env.sh)"
