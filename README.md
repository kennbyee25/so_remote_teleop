# SO-101 Remote Teleop over Tailscale

Teleoperate an [SO-101](https://github.com/TheRobotStudio/SO-ARM100) **follower** arm that is
plugged into one machine from a **leader** arm plugged into another, over Tailscale (or any
TCP network), using stock [LeRobot](https://github.com/huggingface/lerobot) — no
robot-specific server code.

```
  leader machine (client)                       follower machine (server)
 ┌───────────────────────────┐                ┌──────────────────────────┐
 │ leader arm (USB serial)   │                │ follower arm (USB serial)│
 │        │                  │   TCP :7777    │        │                 │
 │ lerobot-teleoperate ──────┼────────────────┼──► socat bridge          │
 │        │                  │  (tailscale)   │   (systemd service)      │
 │   socat PTY tunnel        │                │                          │
 └───────────────────────────┘                └──────────────────────────┘
```

A `socat` PTY on the leader machine makes the remote follower look like a local serial
port, so unmodified `lerobot-teleoperate` drives both arms. Two small lerobot patches make
the Feetech protocol robust to network jitter.

Every machine can play either role, or both at once (one arm each way).

## I want to control someone else's follower  (client / leader side)

Needs: Linux, Python 3.12+, your own leader arm, and the owner's Tailscale IP.

```bash
git clone https://github.com/kennbyee25/so_remote_teleop && cd so_remote_teleop
./install_client.sh        # lerobot==0.5.1[feetech], socat, jitter patches, follower calibration
sudo usermod -aG dialout $USER   # once, then log out/in (serial permission)

# Plug in your leader arm and power it (its own supply — USB alone does not power the motors).
FOLLOWER_HOST=<their-tailscale-ip> ./start_teleop.sh
```

- **First run calibrates your leader** (id `leader`): it must run in an interactive
  terminal. Move every joint to mid-range and press Enter, then sweep each joint through its
  full range. Saved to `~/.cache/huggingface/lerobot/calibration/`.
- The **follower's** calibration ships in `calibration/follower.json` (installed for you), so
  you do not recalibrate someone else's arm. If it prompts about calibration anyway, press
  Enter to keep the one provided.
- Find your leader port with `lerobot-find-port`; override with `LEADER_PORT=/dev/ttyACM1`.
- Put settings in a git-ignored `.env` next to the script to avoid retyping:
  ```
  FOLLOWER_HOST=100.x.y.z
  MAX_REL=off
  ```

## I want someone to control my follower  (server / follower side)

Needs: Linux with systemd, the follower arm plugged in and powered, Tailscale up.

```bash
git clone https://github.com/kennbyee25/so_remote_teleop && cd so_remote_teleop
sudo ./install_server.sh     # installs socat + the arm-serial-bridge systemd service
```

Defaults: serial port `/dev/ttyACM0`, TCP port `7777`, listening **only on this machine's
Tailscale address**. Override with env vars, e.g.
`SERIAL_PORT=/dev/serial/by-id/usb-... TCP_PORT=7778 sudo -E ./install_server.sh`;
`BIND=` (empty) listens on all interfaces. `DRY_RUN=1 ./install_server.sh` prints the unit
without installing. It finishes by printing the exact command the remote user should run.

Then share your calibration with them: copy `~/.cache/huggingface/lerobot/calibration/robots/so_follower/follower.json`
into this repo's `calibration/` (the file for the arm they will drive) and push it.

Make sure the other person can reach you: same tailnet, or share your machine with them
from the Tailscale admin console.

### Safety notes

- The bridge has **no authentication**. Anyone who can reach that TCP port can move the arm
  (and write its servo settings). Keep it bound to the Tailscale address and only share the
  machine with people you trust.
- **One controller at a time.** Two clients interleave writes on the same serial port and the
  arm will jitter or fail. Coordinate who is driving.
- Leader and follower use different power adapters/voltages — do not swap them.

## Options (env vars or `.env`)

| Var | Default | Meaning |
|---|---|---|
| `FOLLOWER_HOST` | — (required) | Tailscale IP/name of the follower's machine (`PI_HOST` also accepted) |
| `FOLLOWER_PORT` | `7777` | bridge TCP port (`PI_TCP` also accepted) |
| `LEADER_PORT` | `/dev/ttyACM0` | leader serial port on this machine |
| `ARM` | `so101` | `so101` or `so100` |
| `LEADER_ID` / `FOLLOWER_ID` | `leader` / `follower` | calibration names |
| `MAX_REL` | `5` | max joint move per step (degrees). `off` = fast mode |
| `LEROBOT_SERIAL_MARGIN_MS` | `400` | extra read-timeout margin for tunnel jitter |
| `LEROBOT_TUNNEL_RETRIES` | `3` | per-motor read retries |
| `LEROBOT_P_COEF` / `LEROBOT_D_COEF` | `32` / `64` | servo position gains (lerobot default P is 16) |
| `LEROBOT_GRIPPER_OVERLOAD` | `45` | gripper stall-torque limit; higher grips harder but heats up |

### Fast mode

```bash
MAX_REL=off ./start_teleop.sh
```

Disables the per-step clamp *and* the position read-back it requires, so goal commands
become one-way writes at full loop rate — much more responsive.

⚠️ With the clamp off, the follower **snaps at full servo speed to wherever the leader is**
the moment torque enables. Match the leader to the follower's pose before starting, and keep a
hand near Ctrl+C.

## Why the lerobot patches?

Stock lerobot assumes local USB (sub-millisecond echo). Over a TCP tunnel:

1. **Read timeouts** (~16–50 ms) are shorter than jitter spikes (~170 ms on a Pi with Wi-Fi
   power save). → timeout margin is now configurable via `LEROBOT_SERIAL_MARGIN_MS`.
2. **Broadcast group sync-reads** (one request, all servos answer back-to-back) don't
   survive the tunnel. → `LEROBOT_NO_SYNC_READ=1` falls back to per-motor reads with retries
   and stale-byte flushing.

The behaviours are opt-in via env vars; unset, patched lerobot behaves like stock. Patches
target lerobot **0.5.1** (`install_client.sh` pins it); re-run `python3 apply_lerobot_patches.py`
after any lerobot reinstall. Measured over Tailscale on one LAN: ~23 Hz full-arm position
reads, 0 failures in 700 consecutive reads.

## Troubleshooting

- **"Full found motor list: {}" on the leader port** — the leader's controller board has no
  power (USB does not power the servos), or the motor cable is loose.
- **PTY never appeared / connection refused** — the follower's bridge isn't up or isn't
  reachable: `tailscale ping <host>`, and on the server `systemctl status arm-serial-bridge`.
- **Intermittent read errors** — raise `LEROBOT_SERIAL_MARGIN_MS`, or move the follower host
  off Wi-Fi power save (`iw dev wlan0 set power_save off`).

## Diagnostics

- `ping_follower.py` — raw Feetech ping of each motor through the tunnel.
- `test_syncread.py` — one-shot multi-motor read check.
- `hammer_test.py` — sustained read-rate/reliability benchmark.
