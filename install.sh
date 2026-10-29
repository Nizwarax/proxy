#!/bin/bash
# =============================================================
#  WGRouter one-command installer
#  https://github.com/Nizwarax/proxy
#
#  Pakai:
#    curl -fsSL https://raw.githubusercontent.com/Nizwarax/proxy/main/install.sh | bash
#    atau non-interaktif:
#    bash install.sh --server
#    bash install.sh --client [file|URL]
# =============================================================
set -e
REPO="Nizwarax/proxy"
BRANCH="main"
DEST="/opt/wgrouter"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

[ "$(id -u)" = 0 ] || { echo -e "${RED}[x] Jalankan sebagai root.${NC}"; exit 1; }

echo -e "${YELLOW}[*] Mengunduh WGRouter dari github.com/$REPO ...${NC}"
mkdir -p "$DEST"
curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" \
    | tar -xz --strip-components=1 -C "$DEST"

[ -f "$DEST/router.sh" ] || { echo -e "${RED}[x] router.sh tidak ada di tarball.${NC}"; exit 1; }
chmod +x "$DEST/router.sh" "$DEST/setup.sh" 2>/dev/null || true
ln -sf "$DEST/router.sh" /usr/local/bin/wgrouter

# dependensi minimal (biarkan router.sh yang pasang sisanya saat dipakai)
if command -v apt-get >/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q curl wireguard-tools iptables >/dev/null 2>&1 || true
fi

echo -e "${GREEN}[+] WGRouter terpasang: /usr/local/bin/wgrouter${NC}"
echo -e "${GREEN}[+] Cek: wgrouter help${NC}"

case "${1:-}" in
    --server) exec bash "$DEST/router.sh" server ;;
    --client) shift; exec bash "$DEST/router.sh" client "${1:-}" ;;
    *)        exec bash "$DEST/setup.sh" ;;
esac
