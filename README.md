# Skrip Bypass IP VPS dengan WireGuard (Serba Otomatis)

## Pendahuluan

Skrip ini menyediakan cara yang sepenuhnya otomatis untuk mengalihkan lalu lintas internet dari sebuah VPS di luar negeri (**VPS-LN**) melalui VPS yang berlokasi di Indonesia (**VPS-ID**). Hasilnya, semua koneksi yang keluar dari VPS-LN akan terlihat menggunakan alamat IP publik milik VPS-ID.

Proses ini diotomatiskan melalui sebuah skrip menu interaktif (`setup.sh`).

## Arsitektur

Anda memerlukan **dua** server VPS untuk menerapkan konfigurasi ini:

1.  **VPS-ID (Server Indonesia)**: Berperan sebagai **Server VPN** atau "Pintu Keluar" (Exit Node).
2.  **VPS-LN (Server Luar Negeri)**: Berperan sebagai **Klien VPN**.

---

## Cara Penggunaan

Cara termudah adalah dengan mengkloning (clone) seluruh repositori ini ke kedua VPS Anda.

**1. Klon Repositori**

Gunakan perintah `git` untuk mengunduh semua file yang diperlukan.
```bash
# Ganti URL_REPOSITORI dengan URL repositori ini yang sebenarnya
git clone URL_REPOSITORI
cd NAMA_DIREKTORI_HASIL_CLONE
```

**2. Jalankan Skrip**

Setelah masuk ke direktori repositori, jalankan skrip `setup.sh` dengan `sudo` di setiap VPS dan ikuti menu yang ditampilkan.
```bash
sudo ./setup.sh
```

---

### Langkah 1: Di VPS Indonesia (Server)

1.  Jalankan `sudo ./setup.sh`.
2.  Pilih opsi **1** untuk **Konfigurasi sebagai Server**.
3.  Skrip akan menggunakan installer lokal untuk menginstal server WireGuard secara otomatis.
4.  Setelah selesai, skrip akan menampilkan isi dari `client.conf`. **Salin dan simpan seluruh konfigurasi ini.** Anda akan membutuhkannya di langkah berikutnya.

### Langkah 2: Di VPS Luar Negeri (Klien)

1.  Jalankan `sudo ./setup.sh`.
2.  Pilih opsi **2** untuk **Konfigurasi sebagai Klien**.
3.  Skrip akan menginstal paket WireGuard yang diperlukan.
4.  Selanjutnya, skrip akan meminta Anda untuk menempelkan (paste) konfigurasi `client.conf` yang Anda dapatkan dari VPS Indonesia.
5.  Tempelkan konfigurasi tersebut, lalu tekan `CTRL+D`.
6.  Skrip akan menyelesaikan sisa konfigurasi secara otomatis, mengaktifkan koneksi, dan melakukan verifikasi.

### Langkah 3: Verifikasi

Setelah konfigurasi klien selesai, skrip akan secara otomatis menampilkan alamat IP publik baru Anda. Jika alamat IP yang ditampilkan adalah milik **VPS Indonesia**, maka setup Anda telah berhasil.

## Catatan Penting

*   Skrip ini perlu dijalankan dengan hak akses `root` atau `sudo`.
*   File `setup.sh` dan `wireguard-installer.sh` harus berada di direktori yang sama saat dijalankan.
