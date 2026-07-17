#!/usr/bin/env python3
"""Sustained read test: mimic calibration's record loop (continuous sync_reads)."""
import os, sys, time
os.environ.setdefault("LEROBOT_NO_SYNC_READ", "1")
os.environ.setdefault("LEROBOT_SERIAL_MARGIN_MS", "400")
from lerobot.robots.so_follower.so_follower import SOFollower
from lerobot.robots.so_follower.config_so_follower import SOFollowerRobotConfig

port = sys.argv[1] if len(sys.argv) > 1 else "/home/kennethyee/follower_tty"
dur = float(sys.argv[2]) if len(sys.argv) > 2 else 25.0
robot = SOFollower(SOFollowerRobotConfig(port=port, id="follower", use_degrees=True))
robot.bus.connect()
print(f"hammering sync_read for {dur:.0f}s ...")
n = fails = 0
t_end = time.time() + dur
worst = 0.0
while time.time() < t_end:
    t0 = time.perf_counter()
    try:
        robot.bus.sync_read("Present_Position", normalize=False)
    except Exception as e:
        fails += 1
        print(f"  FAIL at read {n}: {e}")
    dt = time.perf_counter() - t0
    worst = max(worst, dt)
    n += 1
robot.bus.disconnect()
print(f"done: {n} reads, {fails} failures, rate={n/dur:.1f} Hz, worst read {worst*1000:.0f}ms")
print("PASS" if fails == 0 else "FAIL")
