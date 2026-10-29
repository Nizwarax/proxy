#!/bin/bash
# =============================================================
#  WGRouter — Setup Menu (WireGuard VPS Routing)
#  Repo: https://github.com/Nizwarax/proxy
#  Engine: router.sh (bisa juga dipakai langsung: ./router.sh help)
# =============================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/router.sh"

[ -f "$R" ] || { echo -e "${RED}[x] router.sh tidak ditemukan di $HERE${NC}"; exit 1; }
chmod +x "$R"

show_menu() {
    echo -e "${CYAN}===============================================${NC}"
    echo -e "${CYAN}   WGRouter — WireGuard VPS Routing v1.0${NC}"
    echo -e "${CYAN}===============================================${NC}"
    echo " 1. Setup Server  (VPS Indonesia — exit IP)"
    echo " 2. Setup Klien   (VPS Luar Negeri — paste/URL config)"
    echo " 3. Status lengkap"
    echo " 4. Routing ON / OFF"
    echo " 5. Ganti mode (full / split per-port)"
    echo " 6. Kelola port split-routing"
    echo " 7. Killswitch ON / OFF"
    echo " 8. Watchdog auto-failover ON / OFF"
    echo " 9. Uninstall"
    echo " 0. Keluar"
    echo -e "${CYAN}-----------------------------------------------${NC}"
}

ask() { read -rp "$1" a; echo "$a"; }

case_menu_ports() {
    echo "Port sekarang: $("$R" ports | awk '{print $3}')"
    echo " 1. Tambah port   2. Hapus port"
    case "$(ask 'Pilihan: ')" in
        1) P=$(ask 'Port yang ditambah (spasi utk banyak): '); "$R" port add $P ;;
        2) P=$(ask 'Port yang dihapus: '); "$R" port del $P ;;
    esac
}

while true; do
    show_menu
    c=$(ask 'Masukkan pilihan (0-9): ')
    case $c in
        1) bash "$R" server ;;
        2) SRC=$(ask 'Sumber config [ENTER=paste | path file | URL]: ')
           bash "$R" client "$SRC" ;;
        3) bash "$R" status ;;
        4) case "$(ask 'on/off: ')" in on) "$R" on;; off) "$R" off;; *) echo invalid;; esac ;;
        5) M=$(ask 'mode full/split: '); bash "$R" mode "$M" ;;
        6) case_menu_ports ;;
        7) case "$(ask 'on/off: ')" in on) "$R" killswitch on;; off) "$R" killswitch off;; *) echo invalid;; esac ;;
        8) case "$(ask 'on/off: ')" in on) "$R" watchdog on;; off) "$R" watchdog off;; *) echo invalid;; esac ;;
        9) "$R" uninstall ;;
        0) echo "Keluar."; exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid.${NC}" ;;
    esac
    echo ""
done
