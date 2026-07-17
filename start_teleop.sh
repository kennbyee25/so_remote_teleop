#!/usr/bin/env bash
# Remote teleop from THIS laptop.
#   Leader  = local USB serial (this laptop)
#   Follower = the Pi's /dev/ttyACM0, reached over Tailscale via the Pi's
#              arm-serial-bridge.service (socat TCP-LISTEN:7777 <-> serial @1Mbaud).
#
# This script opens a local PTY that tunnels to the Pi's TCP bridge, so lerobot
# sees the remote follower as an ordinary serial device, then runs teleoperate.
set -euo pipefail

# ---- config (override via env) ----
ARM="${ARM:-so101}"                       # so101 or so100
LEADER_PORT="${LEADER_PORT:-/dev/ttyACM0}"
PI_HOST="${PI_HOST:-100.95.121.11}"
PI_TCP="${PI_TCP:-7777}"
FOLLOWER_TTY="${FOLLOWER_TTY:-$HOME/follower_tty}"
MAX_REL="${MAX_REL:-5}"                    # deg/step safety clamp; "off" = no clamp (fast mode)
# Tolerate serial-over-TCP jitter (Pi Wi-Fi power-save spikes to ~170ms). Lengthens
# only how long a read waits before giving up; successful reads still return instantly.
export LEROBOT_SERIAL_MARGIN_MS="${LEROBOT_SERIAL_MARGIN_MS:-400}"
# Broadcast group-reads don't survive the tunnel; read motors individually instead.
export LEROBOT_NO_SYNC_READ="${LEROBOT_NO_SYNC_READ:-1}"

echo "[teleop] opening PTY tunnel  $FOLLOWER_TTY  <->  $PI_HOST:$PI_TCP"
socat PTY,link="$FOLLOWER_TTY",rawer,b1000000 TCP:"$PI_HOST":"$PI_TCP" &
SOCAT_PID=$!
trap 'echo "[teleop] closing tunnel"; kill $SOCAT_PID 2>/dev/null || true' EXIT

# wait for the pty to appear
for i in $(seq 1 50); do [ -e "$FOLLOWER_TTY" ] && break; sleep 0.1; done
[ -e "$FOLLOWER_TTY" ] || { echo "[teleop] PTY never appeared — is the Pi bridge up?"; exit 1; }
echo "[teleop] tunnel ready."

CLAMP_ARGS=()
if [ "$MAX_REL" != "off" ]; then
  CLAMP_ARGS=(--robot.max_relative_target="$MAX_REL")
else
  echo "[teleop] FAST MODE: safety clamp OFF — follower will snap to the leader's pose at start."
  echo "[teleop]            Match the leader to the follower's pose BEFORE torque enables!"
fi

echo "[teleop] launching lerobot-teleoperate (arm=$ARM, max_rel=$MAX_REL, margin=${LEROBOT_SERIAL_MARGIN_MS}ms)"
lerobot-teleoperate \
  --robot.type="${ARM}_follower" \
  --robot.port="$FOLLOWER_TTY" \
  --robot.id=follower \
  "${CLAMP_ARGS[@]}" \
  --teleop.type="${ARM}_leader" \
  --teleop.port="$LEADER_PORT" \
  --teleop.id=leader
