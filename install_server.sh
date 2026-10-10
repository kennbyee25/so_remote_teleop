#!/usr/bin/env bash
# install_server.sh — run on the machine the FOLLOWER arm is plugged into (Linux + systemd).
# Installs a systemd service that exposes the follower's USB serial port as a TCP
# socket, so a remote leader (see start_teleop.sh) can drive it over Tailscale.
#
#   sudo ./install_server.sh                       # defaults below
#   SERIAL_PORT=/dev/ttyACM1 TCP_PORT=7778 sudo -E ./install_server.sh
#   DRY_RUN=1 ./install_server.sh                  # print the unit, change nothing
set -euo pipefail

SERIAL_PORT="${SERIAL_PORT:-/dev/ttyACM0}"   # prefer a /dev/serial/by-id/... path if you have several adapters
TCP_PORT="${TCP_PORT:-7777}"
BAUD="${BAUD:-1000000}"
SERVICE_NAME="${SERVICE_NAME:-arm-serial-bridge}"
# Listen only on the Tailscale address when there is one (empty = all interfaces).
BIND="${BIND-$(tailscale ip -4 2>/dev/null | head -n1 || true)}"

listen="TCP-LISTEN:${TCP_PORT}"
[ -n "${BIND}" ] && listen+=",bind=${BIND}"
listen+=",reuseaddr,fork,nodelay"

render_unit() {
  cat <<EOF
[Unit]
Description=SO-101 Arm Serial-over-TCP Bridge (${SERIAL_PORT} -> :${TCP_PORT})
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat ${listen} FILE:${SERIAL_PORT},rawer,echo=0,b${BAUD},nonblock
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

if [ "${DRY_RUN:-0}" = "1" ]; then render_unit; exit 0; fi

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

if ! command -v socat >/dev/null; then
  echo "installing socat..."
  if   command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y socat
  elif command -v dnf     >/dev/null; then dnf install -y socat
  elif command -v pacman  >/dev/null; then pacman -S --noconfirm socat
  else echo "install socat with your package manager, then re-run"; exit 1; fi
fi

[ -e "${SERIAL_PORT}" ] || echo "warning: ${SERIAL_PORT} not present right now (is the follower plugged in?)"

render_unit > "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"
systemctl --no-pager --lines=5 status "${SERVICE_NAME}" || true

echo
echo "Bridge up on ${BIND:-0.0.0.0}:${TCP_PORT}. Tell the remote user to run:"
echo "  FOLLOWER_HOST=$(tailscale ip -4 2>/dev/null | head -n1 || echo '<this-machine-tailscale-ip>') FOLLOWER_PORT=${TCP_PORT} ./start_teleop.sh"
