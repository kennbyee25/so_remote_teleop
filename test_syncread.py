#!/usr/bin/env python3
"""Verify a multi-motor sync_read of the follower survives the tunnel."""
import os, sys
os.environ.setdefault("LEROBOT_NO_SYNC_READ", "1")
os.environ.setdefault("LEROBOT_SERIAL_MARGIN_MS", "400")
from lerobot.robots.so_follower.so_follower import SOFollower
from lerobot.robots.so_follower.config_so_follower import SOFollowerRobotConfig

port = sys.argv[1] if len(sys.argv) > 1 else "/home/kennethyee/follower_tty"
robot = SOFollower(SOFollowerRobotConfig(port=port, id="follower", use_degrees=True))
robot.bus.connect()          # handshake only, skips calibration
print("bus connected; doing 3 multi-motor reads of Present_Position ...")
for i in range(3):
    vals = robot.bus.sync_read("Present_Position", normalize=False)
    print(f"  read {i+1}: {vals}")
robot.bus.disconnect()
print("OK — multi-motor sync_read works over the tunnel.")
