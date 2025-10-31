#!/bin/bash

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fungsi untuk menampilkan menu
show_menu() {
    echo -e "${YELLOW}===============================================${NC}"
    echo -e "${YELLOW}   Skrip Setup Otomatis WireGuard Tunnel   ${NC}"
    echo -e "${YELLOW}===============================================${NC}"
    echo "Pilih mode eksekusi:"
    echo "1. Konfigurasi sebagai Server (VPS Indonesia)"
    echo "2. Konfigurasi sebagai Klien (VPS Luar Negeri)"
    echo "3. Keluar"
    echo -e "${YELLOW}-----------------------------------------------${NC}"
}

# Fungsi untuk setup server
setup_server() {
    echo -e "${GREEN}Memulai konfigurasi sebagai Server...${NC}"

    # Cek apakah dijalankan sebagai root
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Skrip ini harus dijalankan sebagai root atau dengan sudo.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Menggunakan skrip instalasi WireGuard lokal...${NC}"
    if [ ! -f "wireguard-installer.sh" ]; then
        echo -e "${RED}File 'wireguard-installer.sh' tidak ditemukan. Pastikan file tersebut ada di direktori yang sama.${NC}"
        exit 1
    fi

    chmod +x wireguard-installer.sh

    echo -e "${YELLOW}Menjalankan instalasi otomatis WireGuard...${NC}"
    if ! ./wireguard-installer.sh --auto; then
        echo -e "${RED}Instalasi WireGuard gagal. Silakan periksa log di atas.${NC}"
        exit 1
    fi

    # Cari file konfigurasi klien
    CLIENT_CONFIG_PATH=$(find /root /home -name "client.conf" -type f 2>/dev/null | head -n 1)

    if [ -z "$CLIENT_CONFIG_PATH" ]; then
        echo -e "${RED}File konfigurasi klien (client.conf) tidak dapat ditemukan setelah instalasi.${NC}"
        exit 1
    fi

    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN}  Instalasi Server WireGuard Berhasil!  ${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${YELLOW}Simpan konfigurasi di bawah ini baik-baik.${NC}"
    echo "Anda akan memerlukannya untuk mengkonfigurasi Klien (VPS Luar Negeri)."
    echo -e "${YELLOW}-------------------[ client.conf ]-------------------${NC}"
    cat "$CLIENT_CONFIG_PATH"
    echo -e "${YELLOW}-----------------------------------------------------${NC}"

    # Membersihkan file installer
    rm -f wireguard-installer.sh
}

# Fungsi untuk setup klien
setup_client() {
    echo -e "${GREEN}Memulai konfigurasi sebagai Klien...${NC}"

    # Cek apakah dijalankan sebagai root
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Skrip ini harus dijalankan sebagai root atau dengan sudo.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Menginstal paket WireGuard...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y wireguard
    elif command -v dnf &> /dev/null; then
        dnf install -y epel-release && dnf install -y wireguard-tools
    elif command -v yum &> /dev/null; then
        yum install -y epel-release && yum install -y wireguard-tools
    else
        echo -e "${RED}Distro Linux tidak didukung. Silakan instal WireGuard secara manual.${NC}"
        exit 1
    fi

    if ! command -v wg &> /dev/null; then
        echo -e "${RED}Instalasi WireGuard gagal. Keluar.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Silakan tempel (paste) isi dari file 'client.conf' Anda.${NC}"
    echo "Tekan CTRL+D setelah selesai menempel."

    # Membaca input dan menyaringnya untuk menghapus baris yang tidak valid
    CONF_CONTENT=$(</dev/stdin | grep -E '^\s*(\[|[^=]+=\s*[^[:space:]]+)')

    if [ -z "$CONF_CONTENT" ]; then
        echo -e "${RED}Tidak ada input konfigurasi yang valid terdeteksi. Keluar.${NC}"
        exit 1
    fi

    echo "$CONF_CONTENT" > /etc/wireguard/wg0.conf

    chmod 600 /etc/wireguard/wg0.conf

    echo -e "${YELLOW}Mengaktifkan koneksi WireGuard...${NC}"
    if ! wg-quick up wg0; then
        echo -e "${RED}Gagal mengaktifkan koneksi WireGuard. Periksa konfigurasi Anda.${NC}"
        exit 1
    fi

    systemctl enable wg-quick@wg0

    echo -e "${YELLOW}Verifikasi koneksi...${NC}"

    # Cek ketersediaan curl
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}Menginstal curl untuk verifikasi...${NC}"
        if command -v apt-get &> /dev/null; then
            apt-get install -y curl
        elif command -v dnf &> /dev/null; then
            dnf install -y curl
        elif command -v yum &> /dev/null; then
            yum install -y curl
        fi
    fi

    NEW_IP=$(curl -s ifconfig.me)

    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN}  Konfigurasi Klien WireGuard Selesai!  ${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    echo "Koneksi WireGuard telah diaktifkan dan akan berjalan otomatis saat boot."
    echo -e "IP Publik Anda sekarang adalah: ${YELLOW}$NEW_IP${NC}"
}

# Loop utama
while true; do
    show_menu
    read -p "Masukkan pilihan Anda (1-3): " choice

    case $choice in
        1)
            setup_server
            break
            ;;
        2)
            setup_client
            break
            ;;
        3)
            echo "Keluar dari skrip."
            exit 0
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid. Silakan coba lagi.${NC}"
            ;;
    esac
    echo ""
done
