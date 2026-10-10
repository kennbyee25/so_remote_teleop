#!/usr/bin/env bash
# Remote teleop: a LOCAL leader arm drives a REMOTE follower arm over Tailscale.
#   Leader   = local USB serial (this machine)
#   Follower = plugged into another machine that runs install_server.sh's bridge
#              (socat TCP-LISTEN <-> serial @1Mbaud).
#
# This script opens a local PTY tunnelled to the follower's TCP bridge, so lerobot
# sees the remote follower as an ordinary serial device, then runs teleoperate.
#
# Config comes from the environment, or from a git-ignored `.env` next to this script.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f .env ] && set -a && . ./.env && set +a

# ---- config ----
FOLLOWER_HOST="${FOLLOWER_HOST:-${PI_HOST:-}}"        # Tailscale IP/name of the follower's host (required)
[ -n "$FOLLOWER_HOST" ] || { echo "set FOLLOWER_HOST=<tailscale-ip> (env or .env)"; exit 1; }
FOLLOWER_PORT="${FOLLOWER_PORT:-${PI_TCP:-7777}}"
ARM="${ARM:-so101}"                                    # so101 or so100
LEADER_PORT="${LEADER_PORT:-/dev/ttyACM0}"
FOLLOWER_TTY="${FOLLOWER_TTY:-$HOME/follower_tty}"
FOLLOWER_ID="${FOLLOWER_ID:-follower}"
LEADER_ID="${LEADER_ID:-leader}"
MAX_REL="${MAX_REL:-5}"                                # deg/step safety clamp; "off" = no clamp (fast mode)
# Tolerate serial-over-TCP jitter (Wi-Fi power-save spikes reach ~170ms). Lengthens
# only how long a read waits before giving up; successful reads still return instantly.
export LEROBOT_SERIAL_MARGIN_MS="${LEROBOT_SERIAL_MARGIN_MS:-400}"
# Broadcast group-reads don't survive the tunnel; read motors individually instead.
export LEROBOT_NO_SYNC_READ="${LEROBOT_NO_SYNC_READ:-1}"
# Servo gains (STS3215): lerobot's default P=16 is mushy and weak under load.
# P=32 is servo firmware default; D=64 damps the extra stiffness.
export LEROBOT_P_COEF="${LEROBOT_P_COEF:-32}"
export LEROBOT_D_COEF="${LEROBOT_D_COEF:-64}"
# Gripper grip strength: raise stall torque so it doesn't give out when grasping.
# (Higher = stronger grip but more heat when stalled; don't leave it clamped for minutes.)
export LEROBOT_GRIPPER_OVERLOAD="${LEROBOT_GRIPPER_OVERLOAD:-45}"

echo "[teleop] opening PTY tunnel  $FOLLOWER_TTY  <->  $FOLLOWER_HOST:$FOLLOWER_PORT"
socat PTY,link="$FOLLOWER_TTY",rawer,b1000000 TCP:"$FOLLOWER_HOST":"$FOLLOWER_PORT",nodelay &
SOCAT_PID=$!
trap 'echo "[teleop] closing tunnel"; kill $SOCAT_PID 2>/dev/null || true' EXIT

# wait for the pty to appear
for i in $(seq 1 50); do [ -e "$FOLLOWER_TTY" ] && break; sleep 0.1; done
[ -e "$FOLLOWER_TTY" ] || { echo "[teleop] PTY never appeared — is the follower's bridge up?"; exit 1; }
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
  --robot.id="$FOLLOWER_ID" \
  "${CLAMP_ARGS[@]}" \
  --teleop.type="${ARM}_leader" \
  --teleop.port="$LEADER_PORT" \
  --teleop.id="$LEADER_ID"
