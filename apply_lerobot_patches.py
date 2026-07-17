#!/usr/bin/env python3
"""Patch an installed lerobot (tested on 0.5.1) for serial-over-TCP remote arms.

Two problems occur when a Feetech arm is reached through a network tunnel
(e.g. socat serial<->TCP on a Pi) instead of local USB:

1. Read timeouts are tuned for local USB (~16-50ms) and give up during
   network jitter spikes.  -> made margin configurable: LEROBOT_SERIAL_MARGIN_MS
2. Broadcast group sync-reads (all servos answer back-to-back) don't survive
   the tunnel.  -> LEROBOT_NO_SYNC_READ=1 falls back to per-motor reads with
   retries + stale-byte flushing (LEROBOT_TUNNEL_RETRIES, default 3).

Idempotent: safe to run twice. Run: python3 apply_lerobot_patches.py
"""

import sys
from pathlib import Path

import lerobot

LEROBOT = Path(lerobot.__file__).parent

PATCHES = [
    # (file, old, new)
    (
        "motors/feetech/feetech.py",
        "import logging\nfrom copy import deepcopy",
        "import logging\nimport os\nfrom copy import deepcopy",
    ),
    (
        "motors/feetech/feetech.py",
        """    self.packet_start_time = self.getCurrentTime()
    self.packet_timeout = (self.tx_time_per_byte * packet_length) + (self.tx_time_per_byte * 3.0) + 50""",
        """    self.packet_start_time = self.getCurrentTime()
    # +margin (ms) tolerates network-tunnel jitter (serial-over-TCP to a remote arm).
    _tunnel_margin = float(os.environ.get("LEROBOT_SERIAL_MARGIN_MS", "50"))
    self.packet_timeout = (self.tx_time_per_byte * packet_length) + (self.tx_time_per_byte * 3.0) + _tunnel_margin""",
    ),
    (
        "motors/feetech/feetech.py",
        """        # set rx timeout
        self.port_handler.setPacketTimeoutMillis((wait_length * tx_time_per_byte) + (3.0 * scs.MAX_ID) + 16.0)""",
        """        # set rx timeout (+margin for network-tunnel jitter; see LEROBOT_SERIAL_MARGIN_MS)
        _tunnel_margin = float(os.environ.get("LEROBOT_SERIAL_MARGIN_MS", "16"))
        self.port_handler.setPacketTimeoutMillis((wait_length * tx_time_per_byte) + (3.0 * scs.MAX_ID) + _tunnel_margin)""",
    ),
    (
        "motors/motors_bus.py",
        "import abc\nimport logging\nfrom collections.abc import Sequence",
        "import abc\nimport logging\nimport os\nfrom collections.abc import Sequence",
    ),
    (
        "motors/motors_bus.py",
        """        self._setup_sync_reader(motor_ids, addr, length)
        for n_try in range(1 + num_retry):
            comm = self.sync_reader.txRxPacket()""",
        """        # Group (broadcast) sync-read has all servos reply back-to-back, which does not
        # survive a serial-over-TCP tunnel to a remote arm. When LEROBOT_NO_SYNC_READ is
        # set, read each motor individually instead (slower, but tunnel-robust).
        if os.environ.get("LEROBOT_NO_SYNC_READ"):
            # Tunnel jitter can drop a reply; retry each motor a few times, flushing any
            # late/stale bytes between attempts so a delayed reply can't corrupt the next read.
            tunnel_retries = int(os.environ.get("LEROBOT_TUNNEL_RETRIES", "3"))
            values: dict[int, int] = {}
            comm = None
            for id_ in motor_ids:
                last_exc = None
                for attempt in range(1 + max(num_retry, tunnel_retries)):
                    try:
                        value, comm, _ = self._read(
                            addr, length, id_, num_retry=0,
                            raise_on_error=True, err_msg=err_msg,
                        )
                        values[id_] = value
                        last_exc = None
                        break
                    except (ConnectionError, RuntimeError) as e:
                        last_exc = e
                        # drain any late reply so it can't desync the next attempt
                        try:
                            self.port_handler.ser.reset_input_buffer()
                        except Exception:
                            pass
                if last_exc is not None:
                    if raise_on_error:
                        raise last_exc
                    values[id_] = 0
            return values, comm if comm is not None else 0

        self._setup_sync_reader(motor_ids, addr, length)
        for n_try in range(1 + num_retry):
            comm = self.sync_reader.txRxPacket()""",
    ),
]


def main():
    changed = skipped = 0
    for rel, old, new in PATCHES:
        f = LEROBOT / rel
        text = f.read_text()
        if new in text:
            skipped += 1
            continue
        if old not in text:
            sys.exit(f"ERROR: pattern not found in {f} — lerobot version mismatch? "
                     f"(tested on 0.5.1)")
        f.write_text(text.replace(old, new, 1))
        print(f"patched: {f}")
        changed += 1
    print(f"done: {changed} applied, {skipped} already present.")


if __name__ == "__main__":
    main()
