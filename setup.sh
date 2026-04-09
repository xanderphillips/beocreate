#!/usr/bin/env bash
# BeoCreate 4-Channel Amplifier setup for Raspberry Pi OS (Debian 12/13)
# Tested on: Debian 13 (trixie), kernel 6.12, aarch64
# Hardware:  Raspberry Pi + HiFiBerry BeoCreate 4-Channel Amplifier
#            4 speakers: L woofer, L tweeter, R woofer, R tweeter
#
# Run as root or with sudo:  sudo bash setup.sh [device-name]
# Default device name: "Record Player"

set -e

DEVICE_NAME="${1:-Record Player}"

# ── helpers ─────────────────────────────────────────────────────────────────
info()  { echo "[INFO]  $*"; }
die()   { echo "[ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run with sudo"

# ── 1. config.txt ────────────────────────────────────────────────────────────
info "Configuring /boot/firmware/config.txt"

CONFIG=/boot/firmware/config.txt

# Disable built-in audio
sed -i 's/^dtparam=audio=on/dtparam=audio=off/' "$CONFIG"

# Enable I2C and SPI
sed -i 's/^#dtparam=i2c_arm=on/dtparam=i2c_arm=on/' "$CONFIG"
sed -i 's/^#dtparam=spi=on/dtparam=spi=on/'         "$CONFIG"

# Hold amp-mute GPIO 27 HIGH from firmware boot (prevents power-on pop)
grep -q 'gpio=27=op,dh' "$CONFIG" || \
    sed -i '/^\[all\]/a gpio=27=op,dh' "$CONFIG"

# Add HiFiBerry DAC+DSP overlay (avoid duplicates)
grep -q 'dtoverlay=hifiberry-dacplusdsp' "$CONFIG" || \
    echo 'dtoverlay=hifiberry-dacplusdsp' >> "$CONFIG"

# ── 2. ALSA default device with L/R channel swap ────────────────────────────
info "Writing /etc/asound.conf"
cat > /etc/asound.conf << 'EOF'
pcm.hifiberry_swapped {
    type plug
    slave.pcm "hw:sndrpihifiberry"
    ttable.0.1 1
    ttable.1.0 1
}

pcm.!default {
    type plug
    slave.pcm "hifiberry_swapped"
}

ctl.!default {
    type hw
    card sndrpihifiberry
}
EOF

# ── 3. HiFiBerry DSP toolkit ─────────────────────────────────────────────────
info "Installing HiFiBerry DSP toolkit"
apt-get install -y git python3-venv libasound2-dev

python3 -m venv /opt/dsptoolkit

# Clone and install from source (not on PyPI)
TMPDIR_DSP=$(mktemp -d)
git clone --depth=1 https://github.com/hifiberry/hifiberry-dsp.git "$TMPDIR_DSP/hifiberry-dsp"
/opt/dsptoolkit/bin/pip install "$TMPDIR_DSP/hifiberry-dsp/src/"

# ── 4. BeoCreate DSP profile ─────────────────────────────────────────────────
info "Installing BeoCreate DSP profile"
mkdir -p /var/lib/hifiberry

# Copy the beocreate-default profile bundled with this repo
cp "$(dirname "$0")/dspprogram.xml" /var/lib/hifiberry/dspprogram.xml

# ── 5. sigmatcpserver systemd service ────────────────────────────────────────
info "Installing sigmatcpserver service"

# Volume limit register address in this profile (4.28 fixed-point, 1.0 = 16777216)
VOLUME_LIMIT_REG=4574
VOLUME_LIMIT_VAL=16777216

cat > /etc/systemd/system/sigmatcpserver.service << EOF
[Unit]
Description=HiFiBerry DSP SigmaTCP Server
After=network.target

[Service]
Type=simple
ExecStartPre=/usr/bin/pinctrl set 27 op dh
ExecStart=/opt/dsptoolkit/bin/sigmatcpserver --localhost --restore --store
ExecStartPost=/bin/sh -c 'sleep 5 && /opt/dsptoolkit/bin/dsptoolkit write-mem ${VOLUME_LIMIT_REG} ${VOLUME_LIMIT_VAL} && /usr/bin/pinctrl set 27 op dl'
ExecStop=/usr/bin/pinctrl set 27 op dh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sigmatcpserver

# ── 6. AirPlay (shairport-sync) ──────────────────────────────────────────────
info "Installing shairport-sync (AirPlay)"
apt-get install -y shairport-sync

cat > /etc/shairport-sync.conf << EOF
general = {
  name = "${DEVICE_NAME}";
  output_backend = "alsa";
};

alsa = {
  output_device = "default";
};

sessioncontrol = {
  allow_session_interruption = "yes";
  session_timeout = 20;
};
EOF

systemctl enable shairport-sync

# ── 7. Spotify Connect (raspotify) ───────────────────────────────────────────
info "Installing raspotify (Spotify Connect)"
curl -sS https://dtcooper.github.io/raspotify/install.sh | sh

cat > /etc/raspotify/conf << EOF
LIBRESPOT_NAME="${DEVICE_NAME}"
LIBRESPOT_BITRATE=320
LIBRESPOT_DEVICE_TYPE=speaker
LIBRESPOT_DISABLE_AUDIO_CACHE=
LIBRESPOT_DISABLE_CREDENTIAL_CACHE=
LIBRESPOT_ENABLE_VOLUME_NORMALISATION=
LIBRESPOT_QUIET=
TMPDIR=/tmp
EOF

systemctl enable raspotify

# ── 8. Bluetooth (bluez-alsa + auto-pairing) ─────────────────────────────────
info "Installing Bluetooth audio"
apt-get install -y bluez-alsa-utils bluez-tools

cat > /etc/bluetooth/main.conf << EOF
[General]
Name = ${DEVICE_NAME}
Class = 0x240418
DiscoverableTimeout = 0
PairableTimeout = 0
FastConnectable = true
Discoverable = true
Pairable = true

[Policy]
AutoEnable = true

[BR]

[LE]

[GATT]

[CSIS]

[AVDTP]
SessionMode = ertm

[AVRCP]

[AdvMon]
EOF

# Override bluealsa-aplay to use our ALSA default device
mkdir -p /etc/systemd/system/bluealsa-aplay.service.d
cat > /etc/systemd/system/bluealsa-aplay.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/bluealsa-aplay -S --pcm=default
EOF

cat > /etc/systemd/system/bt-agent.service << 'EOF'
[Unit]
Description=Bluetooth Auto-Pairing Agent
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/bt-agent -c NoInputNoOutput
Restart=on-failure
RestartSec=5

[Install]
WantedBy=bluetooth.target
EOF

systemctl daemon-reload
systemctl enable bluealsa bluealsa-aplay bt-agent

# ── done ─────────────────────────────────────────────────────────────────────
info "Setup complete."
info "The DSP profile will be programmed on first boot after the reboot below."
info "The device will appear as '${DEVICE_NAME}' on AirPlay, Spotify, and Bluetooth."
echo
echo "Reboot now?  (y/N)"
read -r REPLY
[[ $REPLY =~ ^[Yy]$ ]] && reboot
