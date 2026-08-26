# TAVA arrival station (Raspberry Pi / Orange Pi / Armbian)

Dedicated Linux box at the centre. Students tap an NFC card. Staff still
override on the named iPad kiosk. This appliance calls only
`arrival_station_tap`. It must never store an admin JWT or the service-role key.

The same tree runs on Raspberry Pi OS and Armbian. Prefer a USB CCID reader
(ACR122U or similar) over a board-specific GPIO HAT so Orange Pi and Raspberry
Pi stay interchangeable.

## Hardware

- Raspberry Pi 4/5, Orange Pi 3B, or any Armbian board with USB and wifi
- USB PC/SC reader: ACS ACR122U is the usual cheap CCID reader
- Cards: NTAG213 / NTAG215 / Ultralight. Do **not** buy MIFARE Classic — many
  readers will not expose a usable UID path for those tokens

The iPad kiosk stays tap-name. Do not add Core NFC to `com.tava.TAVAttendance`.

## OS packages

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip pcscd pcsc-tools
sudo systemctl enable --now pcscd
```

ACR122U on Linux sometimes binds to the kernel `pn533` driver instead of
pcscd. If `pcsc_scan` sees nothing:

```bash
echo "blacklist pn533" | sudo tee /etc/modprobe.d/blacklist-pn533.conf
echo "blacklist pn533_usb" | sudo tee -a /etc/modprobe.d/blacklist-pn533.conf
sudo update-initramfs -u
sudo reboot
```

## Install

From a clone of this repository on the box:

```bash
sudo useradd --system --home /opt/tava-station --shell /usr/sbin/nologin tava
sudo mkdir -p /opt/tava-station /etc/tava-station
sudo cp -a station/. /opt/tava-station/
cd /opt/tava-station
sudo python3 -m venv .venv
sudo .venv/bin/pip install -e '.[nfc]'
sudo cp config.example.toml /etc/tava-station/config.toml
sudo chmod 600 /etc/tava-station/config.toml
```

Edit `/etc/tava-station/config.toml`: project URL, **anon** key, station email.
Put the password in `/etc/tava-station/env`:

```
TAVA_STATION_PASSWORD=...
```

```bash
sudo chmod 600 /etc/tava-station/env
sudo cp systemd/tava-arrival-station.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tava-arrival-station
```

Cue page: `http://127.0.0.1:8765`. Optional kiosk browser:

```bash
chromium --kiosk --app=http://127.0.0.1:8765
```

## Local testing without a reader

```bash
cd station
python3 -m venv .venv
.venv/bin/pip install -e .
export TAVA_STATION_CONFIG=/path/to/config.toml
.venv/bin/tava-arrival-station --once 04A1B2C3
```

The local seed user is `station@local.tava.invalid`. Set a Studio password
before signing the daemon in. Flag `nfc_sign_in` must be on in that database
or every tap fails closed.

## Behaviour

Online-first. If wifi is down, use paper and reconcile on the website. Do not
put a service-role key on the box. Unknown cards show the chip UID on the
physical screen so an admin can type it on the web pair form. The website
stores the UID; it shows staff only the last four characters afterwards.

Paper fallback remains. This is not a door reader.
