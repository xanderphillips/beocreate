# BeoCreate 4-Channel Amplifier on Raspberry Pi OS

Setup for running a HiFiBerry BeoCreate 4-Channel Amplifier on vanilla Raspberry Pi OS (Debian 12/13), without HiFiBerry OS.

**Hardware:** Raspberry Pi + BeoCreate 4-Channel Amp  
**Speakers:** L woofer, L tweeter, R woofer, R tweeter  
**OS:** Raspberry Pi OS (Debian 13 trixie, aarch64, kernel 6.12)

## Quick start

```bash
git clone https://github.com/xanderphillips/beocreate.git
cd beocreate
sudo bash setup.sh "My Speaker Name"
```

The device name defaults to `Record Player` if omitted. After rebooting the device will appear under that name on AirPlay, Spotify Connect, and Bluetooth.

### Verify the setup

After rebooting, run the interactive speaker test to confirm channel allocation and crossover:

```bash
bash test-speakers.sh
```

It walks through four tones with prompts and tells you what to expect at each step.

---

## What gets installed

| Component | Package / Source | Purpose |
|---|---|---|
| HiFiBerry DAC+DSP driver | kernel overlay `hifiberry-dacplusdsp` | Exposes the amp as an ALSA sound card |
| DSP toolkit | [hifiberry/hifiberry-dsp](https://github.com/hifiberry/hifiberry-dsp) (GitHub) | Programs and manages the ADAU1451 DSP chip |
| BeoCreate DSP profile | `dspprogram.xml` (bundled) | 4-channel crossover — woofer/tweeter split per side |
| shairport-sync 4.x | apt (`shairport-sync`) | AirPlay receiver |
| raspotify / librespot | [dtcooper/raspotify](https://github.com/dtcooper/raspotify) | Spotify Connect receiver, 320 kbps |
| bluez-alsa | apt (`bluez-alsa-utils`) | Routes Bluetooth A2DP audio to ALSA |
| bt-agent | apt (`bluez-tools`) | Auto-accepts Bluetooth pairing (no PIN) |

---

## How it works

### Audio path

```
AirPlay / Spotify / Bluetooth
        │
   ALSA default device
   (L/R channels swapped — physical wiring on this unit)
        │
   hw:sndrpihifiberry  (HiFiBerry DAC+DSP)
        │
   ADAU1451 DSP  ◄── beocreate-default profile
   ├── L woofer  (low-pass)
   ├── L tweeter (high-pass)
   ├── R woofer  (low-pass)
   └── R tweeter (high-pass)
        │
   4× TDA7498E power amplifier channels
        │
   Speakers
```

### Amp mute / pop prevention

The BeoCreate's amp channels are enabled by **GPIO 27** (active low). Driving it HIGH mutes all four channels. The boot sequence is:

1. `/boot/firmware/config.txt` sets GPIO 27 HIGH at firmware boot (before Linux starts) — no pop during kernel init
2. `sigmatcpserver` starts and loads the DSP profile
3. After 5 seconds (DSP settle time), volume limit is set and GPIO 27 is driven LOW — amp enables silently
4. On service stop/shutdown, GPIO 27 goes HIGH again before the DSP is torn down

### DSP volume limit

The `beocreate-default` profile ships with `volumeLimitRegister` at `0.005` (−46 dB). The service sets it to `1.0` (0 dB / 16777216 in 4.28 fixed-point) on every start via:

```
dsptoolkit write-mem 4574 16777216
```

### L/R channel swap

This unit's speakers are wired with left and right physically reversed. The swap is applied in software via an ALSA `ttable` in `/etc/asound.conf` rather than re-wiring.

If your unit is wired correctly, remove the `ttable` lines and point `pcm.!default` directly at `hw:sndrpihifiberry`.

---

## Services

| Service | Enabled | Notes |
|---|---|---|
| `sigmatcpserver` | yes | DSP server — programs ADAU1451 at boot |
| `shairport-sync` | yes | AirPlay |
| `raspotify` | yes | Spotify Connect |
| `bluealsa` | yes | Bluetooth ALSA bridge |
| `bluealsa-aplay` | yes | Plays Bluetooth audio to ALSA default |
| `bt-agent` | yes | Auto-pairing, no PIN |

---

## Testing

Run `bash test-speakers.sh` on the Pi to interactively verify:

| Test | Frequency | Expected |
|---|---|---|
| Left channel | 1 kHz | Sound from left side only |
| Right channel | 1 kHz | Sound from right side only |
| Woofer crossover | 80 Hz | Bass from woofers only, tweeters silent |
| Tweeter crossover | 8 kHz | Hiss from tweeters only, woofers silent |

The script prompts before each tone and gives diagnostic hints on failure.

---

## Changing the device name

Edit `/etc/shairport-sync.conf`, `/etc/raspotify/conf`, and `/etc/bluetooth/main.conf`, then:

```bash
sudo systemctl restart shairport-sync raspotify bluetooth
```

---

## What HiFiBerry OS also offered (not installed here)

- **Bluetooth speaker** — installed here as `bluez-alsa` + `bt-agent`
- **Snapcast client** — multi-room sync; install `snapclient` from apt if needed
- **BeoCreate web UI** — the `beocreate2` management interface; abandoned upstream

---

## Notes

- HiFiBerry OS is abandoned. Its installer scripts attempted to repartition the SD card and are unsafe on a running system. This repo replaces it entirely using standard packages.
- The DSP profile (`dspprogram.xml`) is the `beocreate-default` profile from the [hifiberry/hifiberry-dsp](https://github.com/hifiberry/hifiberry-dsp) sample files. The ADAU1451's EEPROM retains the program across power cycles; the `sigmatcpserver` verifies and reloads it on boot.
- The DSP toolkit is not on PyPI — it must be installed from GitHub source into a venv at `/opt/dsptoolkit`.
