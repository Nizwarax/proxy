#!/usr/bin/env bash
#
# WGRouter — WireGuard VPS Routing Manager (v1.0)
# Repo: https://github.com/Nizwarax/proxy
#
# Routing engine untuk skenario VPS-LN (klien) yang egress-nya diarahkan
# lewat VPS-ID (server) via WireGuard.
#
# Fitur:
#   full mode    : full tunnel via VPS-ID + preserve SSH (reply dari IP asli tetap direct)
#   split mode   : hanya port-port tertentu (source port) yang lewat VPS-ID
#   killswitch   : tunnel mati = egress diblok, TIDAK jatuh ke IP asli
#   watchdog     : systemd timer 60s — tunnel down -> failover direct, up lagi -> auto sambung
#
# Usage: router.sh <server|client|status|on|off|mode|port|ports|killswitch|watchdog|test|uninstall>
#

VERSION="1.0"
WG_IFACE="${WGR_IFACE:-wg0}"
WG_TABLE="${WGR_TABLE:-51820}"
WG_MARK="${WGR_MARK:-51820}"
KS_TABLE=$(( WG_TABLE + 1 ))
DIR="${WGR_DIR:-/etc/wgrouter}"
CONF="${WGR_CONF:-/etc/wireguard/$WG_IFACE.conf}"
STATE="$DIR/state"
WD_FLAG="$DIR/.wd-down"
LOG="$DIR/wgrouter.log"
BIN="/usr/local/bin/wgrouter"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { printf '%s\n' "$1" >> "$LOG" 2>/dev/null || true; }
info()    { printf "${GREEN}[+]${NC} %s\n" "$1"; }
warn()    { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
die()     { printf "${RED}[x]${NC} %s\n" "$1" >&2; exit 1; }
have()    { command -v "$1" >/dev/null 2>&1; }
need_root(){ [ "$(id -u)" = 0 ] || die "Jalankan sebagai root (sudo)."; }

# ---------------------------------------------------------------- state ----
state_get() {
    local key="$1" def="${2:-}"
    [ -f "$STATE" ] || { printf '%s' "$def"; return; }
    local v
    v=$(grep -E "^${key}=" "$STATE" 2>/dev/null | tail -1 | cut -d= -f2-)
    printf '%s' "${v:-$def}"
}
state_set() {
    mkdir -p "$DIR"
    local key="$1" val="$2" tmp="$STATE.tmp"
    touch "$STATE"
    grep -vE "^${key}=" "$STATE" > "$tmp" 2>/dev/null || true
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$STATE"
}

# ---------------------------------------------------------------- net ------
wan_if()   { ip -4 route show default 2>/dev/null | awk '{print $5; exit}'; }
wan_ip()   { ip -4 addr show dev "$(wan_if)" 2>/dev/null | awk '/inet /{split($2,a,"/");print a[1];exit}'; }
rules_on() { ip rule show 2>/dev/null | grep -q "lookup $WG_TABLE"; }

# Ambil IP server di dalam tunnel (x.x.x.1 / ::1) dari Address di conf klien.
derive_srv_ip() {
    [ -f "$CONF" ] || return 1
    local a
    a=$(awk -F' = ' '/^Address/{print $2; exit}' "$CONF")
    [ -z "$a" ] && return 1
    local v4 v6
    v4=$(printf '%s\n' "$a" | tr ',' '\n' | grep -E '^[0-9]+\.' | head -1)
    if [ -n "$v4" ]; then
        printf '%s.1' "$(echo "$v4" | cut -d/ -f1 | rev | cut -d. -f2- | rev)"
    else
        v6=$(printf '%s\n' "$a" | tr ',' '\n' | grep ':' | head -1)
        [ -n "$v6" ] && printf '%s1' "$(echo "$v6" | cut -d/ -f1 | sed 's/2$/1/')"
    fi
}

# ---------------------------------------------------------- routing core ---
route_tbl_add()    { ip route replace default dev "$WG_IFACE" table "$WG_TABLE" 2>/dev/null || return 1; }
route_tbl_flush()  { ip route flush table "$WG_TABLE" 2>/dev/null || true; }

endpoint_ip() { awk -F' = ' '/^Endpoint/{split($2,a,":"); print a[1]; exit}' "$CONF" 2>/dev/null; }

# Host-route endpoint selalu lewat WAN (anti recursive routing)
endpoint_route_add() {
    local ep; ep=$(endpoint_ip)
    [ -n "$ep" ] || return 0
    local gw dev; gw=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}'); dev=$(wan_if)
    [ -n "$dev" ] || return 0
    if [ -n "$gw" ] && [ "$ep" != "$gw" ]; then
        ip route replace "$ep/32" via "$gw" dev "$dev" 2>/dev/null || ip route replace "$ep/32" dev "$dev" 2>/dev/null || true
    else
        ip route replace "$ep/32" dev "$dev" 2>/dev/null || true
    fi
    state_set EP_ROUTE "$ep"
}
endpoint_route_del() {
    local ep; ep=$(state_get EP_ROUTE "")
    [ -n "$ep" ] && ip route del "$ep/32" 2>/dev/null || true
    state_set EP_ROUTE ""
}

# pasang rule dengan prioritas tertentu: kernel menolak "File exists" kalau
# prioritas sudah ditempati rule lain (spec beda pun ditolak) — jadi selalu
# del-by-priority dulu, baru add.
rule_put() {
    local prio="$1"; shift
    ip rule del priority "$prio" 2>/dev/null || true
    ip rule add "$@" priority "$prio" 2>/dev/null
}

full_rules_on() {
    local wanip; wanip=$(wan_ip)
    # 1) trafik ke endpoint WG: SELALU direct (anti loop)
    local ep; ep=$(endpoint_ip)
    [ -n "$ep" ] && rule_put 32700 to "$ep" lookup main
    # 2) reply dari IP asli (SSH masuk) tetap direct
    [ -n "$wanip" ] && rule_put 32701 from "$wanip" lookup main
    # 3) UDP WireGuard sendiri di-mark biar lolos dari rule tunnel (anti recursive);
    #    paket ber-mark dilempar ke rule main bawaan (32766) via host-route endpoint
    wg set "$WG_IFACE" fwmark "$WG_MARK" 2>/dev/null || true
    # 4) sisanya -> tunnel
    rule_put 32764 not fwmark "$WG_MARK" table "$WG_TABLE"
    endpoint_route_add
    route_tbl_add
}
full_rules_off() {
    ip rule del priority 32700 2>/dev/null || true
    ip rule del priority 32701 2>/dev/null || true
    ip rule del priority 32764 2>/dev/null || true
    ip rule del priority 32765 2>/dev/null || true
    wg set "$WG_IFACE" fwmark 0 2>/dev/null || true
    endpoint_route_del
    route_tbl_flush
}

ipt() { iptables -t mangle "$@"; }

split_chain_apply() {
    ipt -N WGR 2>/dev/null || true
    ipt -F WGR
    local p
    for p in $(state_get PORTS); do
        ipt -A WGR -p tcp -m multiport --sports "$p"  -j MARK --set-xmark "$WG_MARK" 2>/dev/null
        ipt -A WGR -p udp -m multiport --sports "$p"  -j MARK --set-xmark "$WG_MARK" 2>/dev/null
    done
    ipt -C OUTPUT     -j WGR 2>/dev/null || ipt -A OUTPUT -j WGR
    ipt -C PREROUTING -j WGR 2>/dev/null || ipt -A PREROUTING -j WGR
}
split_chain_remove() {
    ipt -D OUTPUT     -j WGR 2>/dev/null || true
    ipt -D PREROUTING -j WGR 2>/dev/null || true
    ipt -F WGR 2>/dev/null || true
    ipt -X WGR 2>/dev/null || true
}
split_rules_on() {
    local ep; ep=$(endpoint_ip)
    [ -n "$ep" ] && rule_put 32700 to "$ep" lookup main
    endpoint_route_add
    split_chain_apply
    rule_put 32764 fwmark "$WG_MARK" table "$WG_TABLE"
    # src harus 10.7.0.2 saat keluar via wg0: aplikasi bind src IP asli pada
    # lookup pertama (sebelum mark) — tanpa MASQ, inner-src ditolak allowed-ips server
    iptables -t nat -C POSTROUTING -o "$WG_IFACE" -m mark --mark "$WG_MARK" -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -o "$WG_IFACE" -m mark --mark "$WG_MARK" -j MASQUERADE
    route_tbl_add
}
split_rules_off() {
    split_chain_remove
    iptables -t nat -D POSTROUTING -o "$WG_IFACE" -m mark --mark "$WG_MARK" -j MASQUERADE 2>/dev/null || true
    ip rule del priority 32700 2>/dev/null || true
    ip rule del priority 32764 2>/dev/null || true
    endpoint_route_del
    route_tbl_flush
}

routing_on() {
    [ -f "$CONF" ] || die "Config $CONF belum ada. Jalankan 'wgrouter client' dulu."
    ip link show "$WG_IFACE" >/dev/null 2>&1 || wg-quick up "$CONF" || die "Gagal wg-quick up"
    local mode; mode=$(state_get MODE full)
    # bersihkan rules/chain mode LAIN dulu (rule dengan prioritas sama tidak bisa
    # dipasang berdampingan — kernel menolak dengan "File exists")
    if [ "$mode" = "split" ]; then
        full_rules_off
        split_rules_on
    else
        split_rules_off
        full_rules_on
    fi
    state_set WD_WANT 1
    rm -f "$WD_FLAG"
    info "Routing AKTIF (mode: $mode) — egress via VPS-ID"
}
routing_off() {
    full_rules_off
    split_rules_off
    state_set WD_WANT 0
    info "Routing MATI — egress direct (IP asli VPS)"
}

killswitch_on() {
    ip route replace blackhole default table "$KS_TABLE"
    local mode; mode=$(state_get MODE full)
    if [ "$mode" = "split" ]; then
        # split: hanya trafik ter-mark yang diblok saat tunnel mati
        rule_put 32765 fwmark "$WG_MARK" lookup "$KS_TABLE"
    else
        # full: semua trafik user diblok, TAPI UDP WireGuard (ber-mark) tetap lolos
        rule_put 32765 not fwmark "$WG_MARK" lookup "$KS_TABLE"
    fi
    state_set KS 1
    info "Killswitch ON — egress diblok kalau tunnel mati"
}
killswitch_off() {
    ip rule del priority 32765 2>/dev/null || true
    ip route flush table "$KS_TABLE" 2>/dev/null || true
    state_set KS 0
    info "Killswitch OFF"
}

# -------------------------------------------------------------- watchdog ---
probe_tunnel() {
    local srv; srv=$(state_get SRV_IP)
    [ -n "$srv" ] || return 1
    # 2 percobaan: setelah wg0 down/up, handshake butuh waktu — jangan buru-buru
    # menyimpulkan tunnel mati (recovery) ataupun gagal (failover)
    ping -c1 -W2 -I "$WG_IFACE" "$srv" >/dev/null 2>&1 && return 0
    sleep 2
    ping -c1 -W2 -I "$WG_IFACE" "$srv" >/dev/null 2>&1
}

watchdog_check() {
    [ -f "$CONF" ] || exit 0
    if probe_tunnel; then
        if [ -f "$WD_FLAG" ]; then
            rm -f "$WD_FLAG"
            routing_on
            log "$(date -Is) watchdog: tunnel pulih -> routing ON"
        fi
    else
        if [ ! -f "$WD_FLAG" ] && [ "$(state_get WD_WANT 1)" = "1" ] && rules_on; then
            touch "$WD_FLAG"
            routing_off
            log "$(date -Is) watchdog: tunnel MATI -> failover direct"
        fi
    fi
}

wd_install() {
    cp -f "$(readlink -f "$0")" "$BIN" 2>/dev/null || die "Gagal install ke $BIN"
    chmod +x "$BIN"
    mkdir -p /etc/systemd/system
    cat > /etc/systemd/system/wg-router-watchdog.service <<EOF
[Unit]
Description=WGRouter tunnel watchdog (failover)
After=network-online.target wg-quick@$WG_IFACE.service

[Service]
Type=oneshot
ExecStart=$BIN watchdog-check
EOF
    cat > /etc/systemd/system/wg-router-watchdog.timer <<EOF
[Unit]
Description=WGRouter watchdog timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
Unit=wg-router-watchdog.service

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now wg-router-watchdog.timer
    state_set WD 1
    info "Watchdog terpasang: systemd timer tiap 60 detik"
}
wd_remove() {
    systemctl disable --now wg-router-watchdog.timer 2>/dev/null || true
    rm -f /etc/systemd/system/wg-router-watchdog.service /etc/systemd/system/wg-router-watchdog.timer
    systemctl daemon-reload
    state_set WD 0
    info "Watchdog dilepas"
}

# --------------------------------------------------------------- client ----
install_pkgs() {
    local pkgs="$*"
    if have apt-get; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -q $pkgs >/dev/null 2>&1
    elif have dnf; then
        dnf install -y -q $pkgs >/dev/null 2>&1
    elif have yum; then
        yum install -y -q $pkgs >/dev/null 2>&1
    fi
}

read_conf_input() {
    # $1 = file | URL | (kosong = paste interaktif, akhiri baris END)
    local src="$1" out="$2"
    if [ -n "$src" ]; then
        if printf '%s' "$src" | grep -qE '^https?://'; then
            curl -fsSL "$src" -o "$out" || die "Gagal unduh $src"
        elif [ -f "$src" ]; then
            cp "$src" "$out"
        else
            die "File tidak ditemukan: $src"
        fi
    else
        warn "Tempel isi client.conf, akhiri dengan baris berisi END lalu Enter:"
        : > "$out"
        local line
        while IFS= read -r line; do
            [ "$line" = "END" ] && break
            printf '%s\n' "$line" >> "$out"
        done
    fi
}

sanitize_conf() {
    # buang baris sampah, sisakan section + KEY = VAL; injek Table=off di [Interface]
    local in="$1" out="$2" tmp
    grep -E '^\s*\[|^\s*[A-Za-z][A-Za-z0-9_-]*\s*=' "$in" | sed 's/\r$//' > "$out"
    if ! grep -q '^Table' "$out"; then
        tmp="$out.tmp"
        awk 'BEGIN{s=0} /^\[Interface\]/{print; print "Table = off"; s=1; next} {print}' "$out" > "$tmp"
        mv "$tmp" "$out"
    fi
}

validate_conf() {
    local conf="$1"
    grep -q '^\s*PrivateKey\s*=' "$conf"      || die "PrivateKey tidak ada di config"
    grep -q '^\s*\[Peer\]'     "$conf"        || die "Section [Peer] tidak ada di config"
    grep -q '^\s*PublicKey\s*=' "$conf"       || die "PublicKey peer tidak ada di config"
    grep -q '^\s*Endpoint\s*=' "$conf"        || die "Endpoint tidak ada di config"
    grep -q '^Table\s*='       "$conf"        || die "Table=off gagal diinjeksi"
    info "Validasi config OK"
}

do_client() {
    need_root
    local src="${1:-}"
    have wg || { install_pkgs wireguard-tools; have wg || die "wireguard-tools gagal terpasang"; }
    have iptables || install_pkgs iptables
    have resolvconf || have openresolv || install_pkgs openresolv resolvconf
    have curl || install_pkgs curl

    local raw="$DIR/raw.conf"
    mkdir -p "$DIR"
    read_conf_input "$src" "$raw"
    sanitize_conf "$raw" "$CONF"
    validate_conf "$CONF"
    chmod 600 "$CONF"

    state_set SRV_IP "$(derive_srv_ip || true)"
    state_set MODE "$(state_get MODE full)"

    # iface lama masih hidup? matikan dulu biar bersih
    wg-quick down "$WG_IFACE" >/dev/null 2>&1 || true
    routing_off >/dev/null 2>&1 || true

    wg-quick up "$CONF" || die "wg-quick up gagal — cek config"
    routing_on
    [ "$(state_get WD 0)" = "1" ] && wd_install

    printf "\n${GREEN}===============================================${NC}\n"
    printf "${GREEN}  Client WGRouter terpasang${NC}\n"
    printf "${GREEN}===============================================${NC}\n"
    info "Config : $CONF"
    info "State  : $STATE"
    info "Cek    : 'wgrouter status' | ganti mode: 'wgrouter mode split'"
    info "Port   : 'wgrouter port add 20001 20002' (split mode)"
}

# --------------------------------------------------------------- server ----
do_server() {
    need_root
    local here
    here="$(cd "$(dirname "$0")" && pwd)"
    local inst="$here/wireguard-installer.sh"
    if ! have wg || ! ls /etc/wireguard/wg0.conf >/dev/null 2>&1; then
        [ -f "$inst" ] || die "wireguard-installer.sh tidak ada di $here"
        chmod +x "$inst"
        warn "Menjalankan installer WireGuard (server VPS-ID)..."
        "$inst" --auto || die "Instalasi WireGuard gagal"
    else
        info "WireGuard server sudah terpasang — lewati installer"
    fi
    # pastikan forwarding persist
    mkdir -p /etc/sysctl.d
    grep -q 'net.ipv4.ip_forward' /etc/sysctl.d/99-wgrouter.conf 2>/dev/null || \
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.d/99-wgrouter.conf
    sysctl -e -q -w net.ipv4.ip_forward=1

    local cconf="/etc/wireguard/client.conf"
    [ -f "$cconf" ] || cconf=$(find /etc/wireguard -name 'client*.conf' -o -name 'wg_client*.conf' 2>/dev/null | head -1)
    printf "\n${GREEN}===============================================${NC}\n"
    printf "${GREEN}  Server VPS-ID siap${NC}\n"
    printf "${GREEN}===============================================${NC}\n"
    [ -n "$cconf" ] && [ -f "$cconf" ] && { info "Config klien di bawah — salin ke VPS-LN:"; echo "-----8<-----"; cat "$cconf"; echo "----->8-----"; } || warn "File client.conf tidak ketemu — cek /etc/wireguard/"
    info "Di VPS-LN jalankan: wgrouter client  (paste config di atas)"
}

# --------------------------------------------------------------- status ----
do_status() {
    local mode ports ks wd
    mode=$(state_get MODE "-"); ports=$(state_get PORTS "-"); ks=$(state_get KS 0); wd=$(state_get WD 0)
    printf "${CYAN}== WGRouter v%s ==${NC}\n" "$VERSION"
    printf "Mode       : %s\n" "$mode"
    printf "Split ports: %s\n" "$ports"
    printf "Killswitch : %s\n" "$([ "$ks" = 1 ] && echo ON || echo off)"
    printf "Watchdog   : %s\n" "$([ "$wd" = 1 ] && echo "ON (timer 60s)" || echo off)"
    printf "WAN iface  : %s (%s)\n" "$(wan_if)" "$(wan_ip)"
    if ip link show "$WG_IFACE" >/dev/null 2>&1; then
        printf "Tunnel     : ${GREEN}UP${NC} (%s)\n" "$WG_IFACE"
        wg show "$WG_IFACE" latest-handshakes 2>/dev/null | while read -r pub ts; do
            [ "$ts" = "0" ] && printf "  handshake: BELUM PERNAH\n" || printf "  handshake: %ss lalu\n" "$(( $(date +%s) - ts ))"
        done
        if probe_tunnel; then
            printf "Probe      : ${GREEN}OK${NC} (server %s reachable)\n" "$(state_get SRV_IP '?')"
        else
            printf "Probe      : ${RED}GAGAL${NC} (server %s tidak merespon di dalam tunnel)\n" "$(state_get SRV_IP '?')"
        fi
    else
        printf "Tunnel     : ${RED}DOWN${NC}\n"
    fi
    if rules_on; then printf "Routing    : ${GREEN}AKTIF${NC}\n"; else printf "Routing    : ${YELLOW}direct${NC} (tunnel tidak dipakai)\n"; fi
    printf "Rules      :\n"
    ip rule show 2>/dev/null | grep -E "32700|32764|32765|32766" | sed 's/^/  /'
}

# ----------------------------------------------------------------- main ----
main() {
case "${1:-}" in
    server)        do_server ;;
    client)        shift; do_client "$@" ;;
    status)        do_status ;;
    on)            need_root; routing_on ;;
    off)           need_root; routing_off ;;
    mode)          need_root
                   case "${2:-}" in
                       full|split)
                           routing_off >/dev/null 2>&1 || true
                           state_set MODE "$2"
                           routing_on ;;
                       *) die "Pakai: $0 mode full|split" ;;
                   esac ;;
    port)          need_root
                   case "${2:-}" in
                       add) shift 2; [ -n "${1:-}" ] || die "Pakai: $0 port add 20001 20002"
                            state_set PORTS "$(printf '%s %s ' "$(state_get PORTS)" "$*" | tr ' ' '\n' | sed '/^$/d' | sort -un | tr '\n' ' ' | sed 's/ $//')"
                            info "Ports: $(state_get PORTS)"
                            [ "$(state_get MODE full)" = "split" ] && rules_on && split_chain_apply ;;
                       del) shift 2; [ -n "${1:-}" ] || die "Pakai: $0 port del 20001"
                            state_set PORTS "$(printf '%s\n' $(state_get PORTS) $* | sort -un | comm -23 - <(printf '%s\n' "$@" | sort -un) | tr '\n' ' ' | sed 's/ $//')"
                            info "Ports: $(state_get PORTS)"
                            [ "$(state_get MODE full)" = "split" ] && rules_on && split_chain_apply ;;
                       *) die "Pakai: $0 port add|del <PORT...>" ;;
                   esac ;;
    ports)         printf "Split ports: %s\n" "$(state_get PORTS '-')" ;;
    killswitch)    need_root
                   case "${2:-}" in
                       on)  killswitch_on ;;
                       off) killswitch_off ;;
                       *)   die "Pakai: $0 killswitch on|off" ;;
                   esac ;;
    watchdog)      need_root
                   case "${2:-}" in
                       on)    wd_install ;;
                       off)   wd_remove ;;
                       check) watchdog_check ;;
                       *)     die "Pakai: $0 watchdog on|off" ;;
                   esac ;;
    test)          do_status; echo; ping -c2 -W3 -I "$WG_IFACE" "$(state_get SRV_IP)" 2>&1 | tail -2 ;;
    uninstall)     need_root
                   wd_remove
                   routing_off
                   killswitch_off
                   wg-quick down "$WG_IFACE" 2>/dev/null || true
                   [ -f "$CONF" ] && mv "$CONF" "$CONF.bak.$(date +%s)"
                   rm -rf "$DIR"
                   info "WGRouter dibersihkan (config dibackup)" ;;
    ""|-h|--help|help)
                   printf "WGRouter v%s — WireGuard VPS Routing Manager\n\n" "$VERSION"
                   printf "  %-22s %s\n" "server"                "Setup VPS ini sebagai server (VPS-ID)"
                   printf "  %-22s %s\n" "client [file|URL]"     "Setup VPS ini sebagai klien (VPS-LN)"
                   printf "  %-22s %s\n" "status"                "Status lengkap tunnel + routing"
                   printf "  %-22s %s\n" "on / off"              "Nyalakan / matikan routing via tunnel"
                   printf "  %-22s %s\n" "mode full|split"       "Ganti mode routing"
                   printf "  %-22s %s\n" "port add|del <PORT...> " "Kelola port split-routing"
                   printf "  %-22s %s\n" "killswitch on|off"     "Blok egress saat tunnel mati"
                   printf "  %-22s %s\n" "watchdog on|off"       "Auto-failover systemd timer"
                   printf "  %-22s %s\n" "test"                  "Diagnostik"
                   printf "  %-22s %s\n" "uninstall"             "Bersihkan semua" ;;
    *)             die "Perintah tidak dikenal: $1 (lihat $0 help)" ;;
esac
}

# hanya jalankan dispatcher bila dieksekusi langsung (bukan di-source untuk uji)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
