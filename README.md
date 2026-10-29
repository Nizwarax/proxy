# WGRouter — Routing VPS via WireGuard (VPS-LN → VPS-ID)

Routing engine untuk mengarahkan egress sebuah VPS Luar Negeri (**VPS-LN**) melalui VPS Indonesia (**VPS-ID**) via WireGuard — semua koneksi keluar VPS-LN terlihat memakai IP publik VPS-ID.

**Diuji dengan WireGuard + policy routing asli di lab network-namespace (bukan simulasi) — 14/14 uji lulus.**

---

## Fitur

| Fitur | Keterangan |
|---|---|
| **Full mode** | Semua egress via VPS-ID + *SSH tetap aman* (reply dari IP asli VPS tetap keluar direct, sesi SSH masuk tidak putus) |
| **Split mode** | Hanya port tertentu (source port) yang lewat VPS-ID — mis. port proxy 20001-20005 egress-nya jadi IP VPS-ID, sisanya (apt, SSH, lainnya) tetap direct |
| **Killswitch** | Tunnel mati = egress diblok (blackhole), **tidak jatuh/bocor ke IP asli** — port non-split tetap jalan normal di split mode |
| **Watchdog** | Timer systemd tiap 60 detik: tunnel down → auto failover ke direct; tunnel pulih → auto sambung kembali |
| **Status lengkap** | Mode, port, killswitch, watchdog, umur handshake, probe tunnel, daftar rule aktif |
| **Instal 1 perintah** | `curl … \| bash` |

---

## Instal 1 Perintah

Jalankan di **kedua** VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/Nizwarax/proxy/main/install.sh | bash
```

Menu muncul otomatis. Non-interaktif:

```bash
curl -fsSL https://raw.githubusercontent.com/Nizwarax/proxy/main/install.sh | bash -s -- --server
curl -fsSL https://raw.githubusercontent.com/Nizwarax/proxy/main/install.sh | bash -s -- --client
```

## Cara Lama (git clone)

```bash
git clone https://github.com/Nizwarax/proxy.git && cd proxy
sudo ./setup.sh
```

---

## Alur Kerja

### VPS-ID (server)
1. Jalankan installer → pilih **1 (Server)**.
2. WireGuard terpasang otomatis (`wireguard-installer.sh --auto`), forwarding IP diaktifkan persist.
3. Salin `client.conf` yang ditampilkan.

### VPS-LN (klien)
1. Jalankan installer → pilih **2 (Klien)** → paste `client.conf` (akhiri baris `END`), atau beri path/URL file.
2. Router otomatis: validasi config → injek `Table = off` → `wg-quick up` → pasang policy routing → **full mode aktif**.

### Verifikasi
```bash
wgrouter status        # tunnel, handshake, probe, rules
curl -s ifconfig.me    # harus menampilkan IP VPS-ID (full mode)
```

---

## Contoh Pemakaian Harian

```bash
# split mode: hanya port 20001-20005 yang egress-nya IP VPS-ID
wgrouter mode split
wgrouter port add 20001 20002 20003 20004 20005

# proteksi bocor: kalau tunnel mati, port ter-mark diblok (bukan pakai IP asli)
wgrouter killswitch on

# auto failover + reconnect
wgrouter watchdog on

# lihat semua
wgrouter status
```

## Perintah Lengkap

```
wgrouter server                  Setup VPS ini sebagai server (VPS-ID)
wgrouter client [file|URL]       Setup VPS ini sebagai klien (VPS-LN)
wgrouter status                  Status lengkap tunnel + routing
wgrouter on | off                Nyalakan / matikan routing via tunnel
wgrouter mode full|split         Ganti mode routing
wgrouter port add|del <PORT...>  Kelola port split-routing
wgrouter killswitch on|off       Blok egress saat tunnel mati
wgrouter watchdog on|off         Auto-failover systemd timer (60s)
wgrouter test                    Diagnostik
wgrouter uninstall               Bersihkan semua (config di-backup)
```

---

## Catatan Teknis

- Klien memakai **`Table = off`** + policy routing sendiri (bukan default `wg-quick`), sehingga:
  - Reply dari IP asli VPS-LN (SSH masuk) tetap direct — sesi SSH tidak putus saat full mode.
  - UDP WireGuard sendiri di-`fwmark` + host-route endpoint → **tidak terjadi recursive routing**.
- Split mode memakai mark `iptables mangle` + rule `fwmark` + **MASQUERADE via wg0** — aplikasi yang bind source-port tetap benar (inner-src dipaksa ke IP tunnel, tidak ditolak allowed-ips server).
- Watchdog menyimpan flag failover sehingga tidak menimpa keputusan manual `off` kamu.
- Teruji di lab (netns + WireGuard asli): full-tunnel MASQ, preserve-SSH, split per-port, killswitch anti-bocor, watchdog failover & auto-reconnect — 14/14 PASS.

## Lisensi

MIT — `wireguard-installer.sh` berdasarkan karya [hwdsl2/wireguard-install](https://github.com/hwdsl2/wireguard-install) (Nyr & contributors).
