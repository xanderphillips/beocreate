#!/usr/bin/env bash
# BeoCreate speaker test — channel allocation and crossover verification
# Run on the Raspberry Pi:  bash test-speakers.sh

set -e

DEVICE="default"
DURATION=8   # seconds per test tone
LOOPS=$(( DURATION / 5 + 1 ))

# ── helpers ──────────────────────────────────────────────────────────────────
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
hr()    { printf '%0.s─' {1..60}; echo; }

prompt() {
    echo
    yellow "  Press ENTER when ready, or q+ENTER to quit..."
    read -r input
    [[ "$input" == "q" ]] && { echo "Aborted."; exit 0; }
}

play() {
    local freq=$1 channel=$2
    # channel: 1=left, 2=right, omit=both
    if [[ -n "$channel" ]]; then
        speaker-test -D "$DEVICE" -c 2 -t sine -f "$freq" -l "$LOOPS" -s "$channel" 2>/dev/null
    else
        speaker-test -D "$DEVICE" -c 2 -t sine -f "$freq" -l "$LOOPS" 2>/dev/null
    fi
}

check_deps() {
    command -v speaker-test >/dev/null || { echo "speaker-test not found — install alsa-utils"; exit 1; }
    aplay -D "$DEVICE" /dev/null 2>/dev/null || { echo "ALSA device '$DEVICE' not accessible"; exit 1; }
}

# ── main ─────────────────────────────────────────────────────────────────────
clear
bold "BeoCreate Speaker Test"
hr
echo "Tests channel allocation (L/R) and crossover (woofer/tweeter)."
echo "You will need to be near the speakers for each test."
echo
echo "Speaker layout expected:"
echo "  Left side:  woofer + tweeter"
echo "  Right side: woofer + tweeter"
echo
echo "Each tone plays for ${DURATION} seconds."
hr

check_deps

# ── Test 1: Left channel ──────────────────────────────────────────────────────
bold "Test 1 of 4 — Left channel (1 kHz)"
echo "  You should hear sound from the LEFT side only."
echo "  Both left woofer and left tweeter may fire at 1 kHz."
prompt
green "  ▶ Playing LEFT channel..."
play 1000 1
echo
echo "  Did you hear sound from the LEFT side only? (y/n)"
read -r ans; [[ "$ans" == "n" ]] && yellow "  ✗ Check L/R wiring or the ttable swap in /etc/asound.conf"
[[ "$ans" == "y" ]] && green "  ✓ Left channel OK"

# ── Test 2: Right channel ─────────────────────────────────────────────────────
bold "Test 2 of 4 — Right channel (1 kHz)"
echo "  You should hear sound from the RIGHT side only."
prompt
green "  ▶ Playing RIGHT channel..."
play 1000 2
echo
echo "  Did you hear sound from the RIGHT side only? (y/n)"
read -r ans; [[ "$ans" == "n" ]] && yellow "  ✗ Check L/R wiring or the ttable swap in /etc/asound.conf"
[[ "$ans" == "y" ]] && green "  ✓ Right channel OK"

# ── Test 3: Woofer crossover ──────────────────────────────────────────────────
bold "Test 3 of 4 — Woofer crossover (80 Hz)"
echo "  You should feel/hear deep bass from the WOOFERS only."
echo "  Tweeters should be silent. Touch the cones if needed."
prompt
green "  ▶ Playing 80 Hz (both channels)..."
play 80
echo
echo "  Did only the WOOFERS produce sound? (y/n)"
read -r ans; [[ "$ans" == "n" ]] && yellow "  ✗ Crossover may not be active — check DSP profile with: sudo systemctl status sigmatcpserver"
[[ "$ans" == "y" ]] && green "  ✓ Woofer crossover OK"

# ── Test 4: Tweeter crossover ─────────────────────────────────────────────────
bold "Test 4 of 4 — Tweeter crossover (8 kHz)"
echo "  You should hear high-frequency hiss from the TWEETERS only."
echo "  Woofers should be silent."
prompt
green "  ▶ Playing 8 kHz (both channels)..."
play 8000
echo
echo "  Did only the TWEETERS produce sound? (y/n)"
read -r ans; [[ "$ans" == "n" ]] && yellow "  ✗ Crossover may not be active — check DSP profile with: sudo systemctl status sigmatcpserver"
[[ "$ans" == "y" ]] && green "  ✓ Tweeter crossover OK"

# ── Summary ───────────────────────────────────────────────────────────────────
hr
bold "Test complete."
echo
echo "If any test failed:"
echo "  L/R reversed  →  toggle the ttable swap in /etc/asound.conf"
echo "  No crossover  →  sudo systemctl restart sigmatcpserver"
echo "                   then check: sudo journalctl -u sigmatcpserver -n 20"
echo "  No sound      →  confirm amp is unmuted: pinctrl get 27  (should show 'lo')"
echo
