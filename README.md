# SO-101 Remote Teleop over Tailscale

Teleoperate an [SO-101](https://github.com/TheRobotStudio/SO-ARM100) follower arm
plugged into a Raspberry Pi from a leader arm plugged into your laptop, over
Tailscale (or any TCP network), using stock
[LeRobot](https://github.com/huggingface/lerobot) — no robot-specific server code.

```
  laptop                                        raspberry pi
 ┌───────────────────────────┐                ┌──────────────────────────┐
 │ leader arm (USB serial)   │                │ follower arm (USB serial)│
 │        │                  │   TCP :7777    │        │                 │
 │ lerobot-teleoperate ──────┼────────────────┼──► socat bridge          │
 │        │                  │  (tailscale)   │   (systemd service)      │
 │   socat PTY tunnel        │                │                          │
 └───────────────────────────┘                └──────────────────────────┘
```

The trick: a `socat` PTY on the laptop makes the remote follower look like a
local serial port, so unmodified `lerobot-teleoperate` drives both arms.
Two small lerobot patches make the Feetech protocol robust to network jitter.

## Setup

### Pi (follower side)
```bash
sudo apt install socat
sudo cp pi/arm-serial-bridge.service /etc/systemd/system/
sudo systemctl enable --now arm-serial-bridge
```
Adjust `/dev/ttyACM0` in the unit if your follower enumerates elsewhere.
No Python or lerobot needed on the Pi.

### Laptop (leader side)
```bash
pip install lerobot          # tested with 0.5.1
sudo dnf install socat       # or apt install socat
sudo usermod -aG dialout $USER   # re-login afterwards
python3 apply_lerobot_patches.py # jitter-robustness patches (idempotent)
```

## Run

```bash
PI_HOST=<pi-tailscale-ip> ./start_teleop.sh
```

First run walks you through one-time calibration of each arm (move to middle
pose, then sweep every joint through its range). Calibrations persist in
`~/.cache/huggingface/lerobot/calibration/`.

Options (env vars):

| Var | Default | Meaning |
|---|---|---|
| `PI_HOST` | — | Pi's Tailscale IP |
| `PI_TCP` | `7777` | bridge port |
| `LEADER_PORT` | `/dev/ttyACM0` | leader serial port on the laptop |
| `ARM` | `so101` | `so101` or `so100` |
| `MAX_REL` | `5` | max joint move per step (degrees). `off` = fast mode |
| `LEROBOT_SERIAL_MARGIN_MS` | `400` | extra read-timeout margin for tunnel jitter |
| `LEROBOT_TUNNEL_RETRIES` | `3` | per-motor read retries |

### Fast mode

```bash
MAX_REL=off ./start_teleop.sh
```

Disables the per-step clamp *and* the position read-back it requires, so goal
commands become one-way writes at full loop rate — much more responsive.

⚠️ With the clamp off, the follower **snaps at full servo speed to wherever the
leader is** the moment torque enables. Match the leader to the follower's pose
before starting, and keep a hand near Ctrl+C.

## Why the lerobot patches?

Stock lerobot assumes local USB (sub-millisecond echo). Over a TCP tunnel:

1. **Read timeouts** (~16–50 ms) are shorter than jitter spikes (~170 ms on a
   Pi with Wi-Fi power save). → timeout margin now configurable via
   `LEROBOT_SERIAL_MARGIN_MS`.
2. **Broadcast group sync-reads** (one request, all servos answer back-to-back)
   don't survive the tunnel. → `LEROBOT_NO_SYNC_READ=1` falls back to
   per-motor reads with retries and stale-byte flushing.

Both are opt-in via env vars; unset, patched lerobot behaves identically to
stock. Measured over Tailscale (same LAN): ~23 Hz full-arm position reads,
0 failures in 700 consecutive reads.

## Diagnostics

- `ping_follower.py` — raw Feetech ping of each motor through the tunnel.
- `test_syncread.py` — one-shot multi-motor read check.
- `hammer_test.py` — sustained read-rate/reliability benchmark.
