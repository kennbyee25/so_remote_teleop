#!/usr/bin/env bash
# install_client.sh — run on the machine the LEADER arm is plugged into.
# Installs lerobot (pinned), socat, the jitter patches, and (optionally) the
# calibration for the remote follower so you do not have to recalibrate it.
#
#   ./install_client.sh
#   FOLLOWER_CALIBRATION=calibration/follower.json ./install_client.sh   # default
#   FOLLOWER_CALIBRATION= ./install_client.sh                            # skip
#   PYTHON=python3.12 PIP_ARGS="" ./install_client.sh                    # inside a venv
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

PYTHON="${PYTHON:-python3}"
LEROBOT_VERSION="${LEROBOT_VERSION:-0.5.1}"       # the patches are written against this version
PIP_ARGS="${PIP_ARGS---user}"                     # empty string = no --user (use in a venv)
[ -n "${VIRTUAL_ENV:-}" ] && PIP_ARGS=""
FOLLOWER_CALIBRATION="${FOLLOWER_CALIBRATION-calibration/follower.json}"
FOLLOWER_ID="${FOLLOWER_ID:-follower}"            # must match --robot.id in start_teleop.sh
CALIB_ROOT="${CALIB_ROOT:-$HOME/.cache/huggingface/lerobot/calibration}"

if ! command -v socat >/dev/null; then
  echo "installing socat (needs sudo)..."
  if   command -v apt-get >/dev/null; then sudo apt-get install -y socat
  elif command -v dnf     >/dev/null; then sudo dnf install -y socat
  elif command -v pacman  >/dev/null; then sudo pacman -S --noconfirm socat
  else echo "install socat with your package manager, then re-run"; exit 1; fi
fi

# shellcheck disable=SC2086
"${PYTHON}" -m pip install ${PIP_ARGS} "lerobot[feetech]==${LEROBOT_VERSION}"
"${PYTHON}" apply_lerobot_patches.py

if [ -n "${FOLLOWER_CALIBRATION}" ]; then
  dst="${CALIB_ROOT}/robots/so_follower/${FOLLOWER_ID}.json"
  if [ -e "${dst}" ]; then
    echo "calibration already present, leaving it: ${dst}"
  else
    mkdir -p "$(dirname "${dst}")"
    cp "${FOLLOWER_CALIBRATION}" "${dst}"
    echo "installed follower calibration -> ${dst}"
  fi
fi

id -nG | grep -qw dialout || echo "note: add yourself to the serial group, then re-login:  sudo usermod -aG dialout \$USER"
echo "Done. Next:  FOLLOWER_HOST=<tailscale-ip> ./start_teleop.sh   (see README)"
