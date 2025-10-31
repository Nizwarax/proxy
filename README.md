# Script Bypass IP VPS dengan WireGuard

## Pendahuluan

Skrip dan panduan ini bertujuan untuk mengalihkan (me-routing) semua lalu lintas internet dari sebuah VPS di luar negeri (**VPS-LN**) melalui VPS yang berlokasi di Indonesia (**VPS-ID**). Hasilnya, semua koneksi yang keluar dari VPS-LN akan terlihat menggunakan alamat IP publik milik VPS-ID.

Metode yang digunakan adalah VPN tunnel menggunakan **WireGuard**, yang dikenal sangat cepat, modern, dan memiliki performa tinggi.

## Arsitektur

Anda memerlukan **dua** server VPS untuk menerapkan konfigurasi ini:

1.  **VPS-ID (Server Indonesia)**:
    *   Berperan sebagai **Server VPN** atau "Pintu Keluar" (Exit Node).
    *   Alamat IP publik dari server inilah yang akan digunakan.
2.  **VPS-LN (Server Luar Negeri)**:
    *   Berperan sebagai **Klien VPN**.
    *   Semua lalu lintas internet dari server ini akan dialihkan melalui VPS-ID.

---

## Langkah-Langkah Instalasi

### Langkah 1: Konfigurasi Server di VPS Indonesia

Login ke **VPS Indonesia** Anda melalui SSH, lalu ikuti perintah di bawah ini.

**1. Unduh Skrip Instalasi**

Skrip ini akan mengotomatisasi seluruh proses instalasi server WireGuard.
```bash
wget -O wireguard.sh https://get.vpnsetup.net/wg
```

**2. Jadikan Skrip Dapat Dieksekusi**
```bash
chmod +x wireguard.sh
```

**3. Jalankan Instalasi Otomatis**

Jalankan skrip dengan mode otomatis. Anda perlu menjalankannya sebagai `root` atau menggunakan `sudo`.
```bash
sudo ./wireguard.sh --auto
```
Setelah instalasi selesai, skrip akan secara otomatis membuat file konfigurasi untuk klien pertama, yang biasanya disimpan di lokasi seperti `/home/ubuntu/client.conf` atau `/root/client.conf`.

**4. Lihat dan Salin Konfigurasi Klien**

Buka file konfigurasi klien dan salin seluruh isinya. Anda akan membutuhkannya untuk konfigurasi di VPS Luar Negeri.
```bash
sudo cat /home/ubuntu/client.conf
# atau jika Anda root
cat client.conf
```

---

### Langkah 2: Konfigurasi Klien di VPS Luar Negeri

Login ke **VPS Luar Negeri** Anda melalui SSH, lalu ikuti langkah-langkah berikut.

**1. Instal Paket WireGuard**

*   **Untuk Ubuntu / Debian:**
    ```bash
    sudo apt update
    sudo apt install wireguard -y
    ```
*   **Untuk CentOS / RHEL / Fedora:**
    ```bash
    sudo dnf install epel-release -y
    sudo dnf install wireguard-tools -y
    ```

**2. Buat File Konfigurasi WireGuard**

Buat file konfigurasi baru di direktori WireGuard.
```bash
sudo nano /etc/wireguard/wg0.conf
```

**3. Tempel Konfigurasi Klien**

Tempel (paste) seluruh isi file `client.conf` yang telah Anda salin dari VPS Indonesia ke dalam editor `nano`.

Simpan file dan keluar dengan menekan `Ctrl + X`, lalu `Y`, dan `Enter`.

**4. Amankan File Konfigurasi**

Atur hak akses file agar hanya dapat dibaca oleh `root`.
```bash
sudo chmod 600 /etc/wireguard/wg0.conf
```

---

### Langkah 3: Menjalankan dan Verifikasi

**1. Aktifkan Koneksi VPN**

Jalankan perintah berikut di **VPS Luar Negeri** untuk memulai tunnel WireGuard.
```bash
sudo wg-quick up wg0
```

**2. (Opsional) Aktifkan Otomatis Saat Booting**

Agar koneksi VPN selalu aktif setiap kali server dinyalakan ulang, jalankan perintah ini:
```bash
sudo systemctl enable wg-quick@wg0
```

**3. Verifikasi Alamat IP**

Untuk memastikan semua lalu lintas sudah dialihkan, cek alamat IP publik Anda dari VPS Luar Negeri.
```bash
curl ifconfig.me
```

Jika konfigurasi berhasil, perintah di atas akan menampilkan **alamat IP dari VPS Indonesia** Anda.

## Catatan Penting

*   Pastikan port UDP yang digunakan oleh WireGuard (default: `51820`) terbuka di firewall VPS Indonesia Anda. Skrip instalasi biasanya sudah menanganinya secara otomatis.
*   Kestabilan lingkungan server, terutama di sisi VPS Indonesia, sangat penting. Masalah pada paket manager atau kernel dapat mengganggu instalasi server WireGuard.
