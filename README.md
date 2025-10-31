# Skrip Bypass IP VPS dengan WireGuard (Serba Otomatis)

## Pendahuluan

Skrip ini menyediakan cara yang sepenuhnya otomatis untuk mengalihkan lalu lintas internet dari sebuah VPS di luar negeri (**VPS-LN**) melalui VPS yang berlokasi di Indonesia (**VPS-ID**). Hasilnya, semua koneksi yang keluar dari VPS-LN akan terlihat menggunakan alamat IP publik milik VPS-ID.

Proses ini diotomatiskan melalui sebuah skrip menu interaktif (`setup.sh`).

---

## Perintah Eksekusi Cepat

Ikuti langkah-langkah ini di **kedua** VPS Anda (Indonesia dan Luar Negeri).

**Langkah 1: Unduh Skrip dari Repositori**

Anda perlu menyalin (clone) repositori ini ke dalam VPS Anda.

a. **Salin URL Repositori:**
   Di halaman web repositori ini, klik tombol hijau bertuliskan **`< > Code`**. Salin URL HTTPS yang muncul. Tampilannya akan seperti `https://github.com/nama-pengguna/nama-repositori.git`.

b. **Jalankan Perintah `git clone`:**
   Ganti `URL_YANG_ANDA_SALIN` dengan URL yang baru saja Anda salin, lalu jalankan di terminal VPS Anda.
   ```bash
   git clone https://github.com/Nizwarax/proxy.git
   ```

c. **Masuk ke Direktori:**
   Setelah selesai, sebuah direktori baru akan dibuat. Gunakan perintah `ls` untuk melihat namanya, lalu masuk ke direktori tersebut.
   ```bash
   # Gunakan 'ls' untuk melihat nama direktori baru
   ls

   # Ganti NAMA_DIREKTORI dengan nama yang muncul dari perintah ls
   cd proxy
   ```

**Langkah 2: Jalankan Skrip**

Setelah berada di dalam direktori yang benar, jalankan skrip dengan perintah di bawah ini. Anda harus menggunakan `sudo` karena skrip ini akan melakukan perubahan pada sistem.

```bash
sudo ./setup.sh
```
Skrip akan menampilkan menu. Ikuti alur kerja di bawah ini.

---

## Alur Kerja Detail

### Di VPS Indonesia (Server)

1.  Jalankan `sudo ./setup.sh`.
2.  Pilih opsi **1** untuk **Konfigurasi sebagai Server**.
3.  Skrip akan menginstal server WireGuard secara otomatis.
4.  Setelah selesai, skrip akan menampilkan isi dari `client.conf`. **Salin dan simpan seluruh konfigurasi ini.** Anda akan membutuhkannya untuk VPS Luar Negeri.

### Di VPS Luar Negeri (Klien)

1.  Jalankan `sudo ./setup.sh`.
2.  Pilih opsi **2** untuk **Konfigurasi sebagai Klien**.
3.  Skrip akan menginstal paket WireGuard.
4.  Selanjutnya, skrip akan meminta Anda untuk menempelkan (paste) konfigurasi `client.conf` yang Anda dapatkan dari VPS Indonesia.
5.  Tempelkan konfigurasi tersebut, lalu tekan `CTRL+D`.
6.  Skrip akan menyelesaikan sisanya secara otomatis dan mengaktifkan koneksi.

### Verifikasi

Setelah konfigurasi klien selesai, skrip akan secara otomatis menampilkan alamat IP publik baru Anda. Jika alamat IP yang ditampilkan adalah milik **VPS Indonesia**, maka setup Anda telah berhasil.

## Catatan Penting

*   Skrip ini perlu dijalankan dengan hak akses `root` atau `sudo`.
*   File `setup.sh` dan `wireguard-installer.sh` harus berada di direktori yang sama saat dijalankan.
