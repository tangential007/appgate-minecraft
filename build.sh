#!/usr/bin/env bash
# Build an Appgate appliance customization zip that runs a Minecraft server.
# Run on any Linux box or WSL with internet access (needs curl, python3, tar, zip).
#
#   ./build.sh --accept-eula                 # latest release
#   ./build.sh --accept-eula --version 1.21.4 --out mc.zip
#
# --accept-eula means you accept the Minecraft EULA: https://aka.ms/MinecraftEULA
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src"
VERSION=""
OUT="$HERE/appgate-minecraft.zip"
EULA=false
LIMIT=$((200 * 1024 * 1024))   # Appgate limit for all customizations combined

while [ $# -gt 0 ]; do
    case "$1" in
        --accept-eula) EULA=true ;;
        --version)     VERSION="$2"; shift ;;
        --out)         OUT="$(realpath -m "$2")"; shift ;;
        -h|--help)     sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

[ "$EULA" = true ] || { echo "You must pass --accept-eula (https://aka.ms/MinecraftEULA)" >&2; exit 1; }
for t in curl python3 tar zip sha1sum sha256sum; do
    command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PKG="$WORK/pkg"
mkdir -p "$PKG/data/jre"

json() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$@"; }

# Minecraft server.jar
echo "==> Resolving Minecraft version"
curl -fsSL https://piston-meta.mojang.com/mc/game/version_manifest_v2.json -o "$WORK/manifest.json"
[ -n "$VERSION" ] || VERSION="$(json "$WORK/manifest.json" "d['latest']['release']")"
VURL="$(json "$WORK/manifest.json" "next(v['url'] for v in d['versions'] if v['id']=='$VERSION')")"
curl -fsSL "$VURL" -o "$WORK/version.json"
JAR_URL="$(json "$WORK/version.json" "d['downloads']['server']['url']")"
JAR_SHA1="$(json "$WORK/version.json" "d['downloads']['server']['sha1']")"
JAVA="$(json "$WORK/version.json" "d.get('javaVersion',{}).get('majorVersion',21)")"
echo "    Minecraft $VERSION (needs Java $JAVA)"

echo "==> Downloading server.jar"
curl -fsSL "$JAR_URL" -o "$PKG/data/server.jar"
echo "$JAR_SHA1  $PKG/data/server.jar" | sha1sum -c --quiet

# Eclipse Temurin JRE (Linux x64)
echo "==> Downloading Temurin JRE $JAVA"
curl -fsSL "https://api.adoptium.net/v3/assets/latest/$JAVA/hotspot?architecture=x64&image_type=jre&os=linux&vendor=eclipse" \
    -o "$WORK/jre.json"
JRE_URL="$(json "$WORK/jre.json" "d[0]['binary']['package']['link']")"
JRE_SHA="$(json "$WORK/jre.json" "d[0]['binary']['package']['checksum']")"
curl -fsSL "$JRE_URL" -o "$WORK/jre.tar.gz"
echo "$JRE_SHA  $WORK/jre.tar.gz" | sha256sum -c --quiet
tar -xzf "$WORK/jre.tar.gz" -C "$PKG/data/jre" --strip-components=1
rm -rf "$PKG/data/jre/legal" "$PKG/data/jre/man"   # trim size

# Scripts and config (strip CRLF in case files were edited on Windows)
echo "==> Assembling package"
cp "$SRC/start" "$SRC/stop" "$SRC/status" "$SRC/metadata.txt" "$PKG/"
cp "$SRC/data/minecraft.conf" "$SRC/data/server.properties" "$PKG/data/"
printf '# Accepted at build time (%s)\n# https://aka.ms/MinecraftEULA\neula=true\n' "$(date -u +%FT%TZ)" \
    > "$PKG/data/eula.txt"
sed -i 's/\r$//' "$PKG/start" "$PKG/stop" "$PKG/status" "$PKG/metadata.txt" \
    "$PKG/data/minecraft.conf" "$PKG/data/server.properties"
chmod 0755 "$PKG/start" "$PKG/stop" "$PKG/status"

# Zip: only start/stop/status/metadata.txt/data at the root, no extra attrs
rm -f "$OUT"
(cd "$PKG" && zip -X -r -q "$OUT" start stop status metadata.txt data)

SIZE=$(stat -c %s "$OUT")
echo "==> Built $OUT ($((SIZE / 1024 / 1024)) MB, Minecraft $VERSION, Java $JAVA)"
if [ "$SIZE" -gt "$LIMIT" ]; then
    echo "WARNING: exceeds Appgate's 200 MB customization limit" >&2
    exit 1
fi
