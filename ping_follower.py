#!/usr/bin/env python3
"""Raw Feetech PING over the follower tunnel, with a generous timeout.
Tells us whether the motors reply at all (vs. a lerobot timeout being too short)."""
import sys, time, serial

port = sys.argv[1] if len(sys.argv) > 1 else "/home/kennethyee/follower_tty"
ser = serial.Serial(port, 1000000, timeout=1.5)
time.sleep(0.2); ser.reset_input_buffer()

def ping(mid):
    chk = (~(mid + 2 + 1)) & 0xFF          # id + len(2) + instr(0x01=PING)
    pkt = bytes([0xFF, 0xFF, mid, 0x02, 0x01, chk])
    ser.reset_input_buffer()
    ser.write(pkt); ser.flush()
    t0 = time.perf_counter()
    resp = ser.read(6)                      # status packet is 6 bytes for a bare ping
    dt = (time.perf_counter() - t0) * 1000
    return resp, dt

print(f"pinging ids 1..6 on {port} (timeout 1.5s each)\n")
any_reply = False
for mid in range(1, 7):
    resp, dt = ping(mid)
    if resp and resp[:2] == b"\xff\xff" and len(resp) >= 3 and resp[2] == mid:
        print(f"  id {mid}: REPLY  ({resp.hex()})  rtt={dt:.0f}ms")
        any_reply = True
    elif resp:
        print(f"  id {mid}: partial/garbage: {resp.hex()}  ({dt:.0f}ms)")
    else:
        print(f"  id {mid}: no reply ({dt:.0f}ms)")
ser.close()
print("\n=> motors ARE reachable; lerobot just needs a longer timeout." if any_reply
      else "\n=> NO motor replied: follower likely unpowered, or bridge not reaching the servo bus.")
