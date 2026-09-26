#!/usr/bin/env python3
"""Talk to the E16 over USB-MIDI SysEx, without the OXI App.

  e16push.py list                   scene names in slots 1-16 (home-screen encoders)
  e16push.py version                raw firmware-version reply
  e16push.py push SLOT FILE         replace the script of the scene in SLOT (1-16)

FILE is a .lua (minified like make_scene.py does) or an .oxie16 scene (its "code").
Only the script is sent; the scene's pages, labels and variables stay as they are.
Reopen the scene on the E16 to run the new code. Protocol: docs/e16-lua-notes.md.
Needs mido + python-rtmidi.
"""
import json
import os
import sys
import time

import mido

sys.path.insert(0, os.path.dirname(__file__))
import make_scene  # noqa: E402

PREFIX = [0x00, 0x21, 0x5B, 0x02, 0x01]       # OXI manufacturer ID, E16
ACK = PREFIX + [0x08, 0x53]
SCRIPT_BYTES = 8192                           # the device's script buffer; the app caps code at 8000


def pack7(data):
    """7 bytes -> 8: a byte of high bits (bit j = byte j), then the low 7 bits of each."""
    out = []
    for i in range(0, len(data), 7):
        g = data[i:i + 7]
        out.append(sum(1 << j for j, x in enumerate(g) if x & 0x80))
        out += [x & 0x7F for x in g]
    return out


def unpack7(data):
    out = bytearray()
    for i in range(0, len(data), 8):
        m = data[i]
        out += bytes(x | (0x80 if m >> j & 1 else 0) for j, x in enumerate(data[i + 1:i + 8]))
    return bytes(out)


def stm32_crc(data):
    """STM32 hardware CRC-32: poly 0x04C11DB7, init 0xFFFFFFFF, little-endian words, no reflection."""
    crc = 0xFFFFFFFF
    for i in range(0, len(data), 4):
        crc ^= int.from_bytes(data[i:i + 4].ljust(4, b"\0"), "little")
        for _ in range(32):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if crc & 0x80000000 else (crc << 1) & 0xFFFFFFFF
    return crc


def upload_msg(kind, slot, index, body):
    """kind 0 = scene header, 1 = page (index 0-11), 4 = script; slot 0-15."""
    n = len(body)
    payload = ((n + 8).to_bytes(4, "big") + b"\x11" + n.to_bytes(2, "big") + b"\0"
               + body + stm32_crc(body).to_bytes(4, "big"))
    return PREFIX + [0x08, kind, slot, index] + pack7(payload)


class E16:
    def __init__(self):
        name = next((n for n in mido.get_output_names() if "E16" in n), None)
        if not name:
            sys.exit("no OXI E16 MIDI port found")
        self.out = mido.open_output(name)
        self.inp = mido.open_input(next(n for n in mido.get_input_names() if "E16" in n))

    def request(self, data, timeout=2.0):
        for _ in self.inp.iter_pending():
            pass
        self.out.send(mido.Message("sysex", data=data))
        end = time.time() + timeout
        while time.time() < end:
            for m in self.inp.iter_pending():
                if m.type == "sysex" and list(m.data[:5]) == PREFIX:
                    return list(m.data)
            time.sleep(0.005)
        return None

    def version(self):
        r = self.request(PREFIX + [0x03, 0x00])
        # layout unknown: fw 1.2.0 replies 03 00 03 01 02 0E 03 02 02 0E 03 00 00 00
        return r and " ".join("%02X" % x for x in r[5:])

    def scene_name(self, slot):
        r = self.request(PREFIX + [0x07, 0x00, slot] + [0] * 6)
        if not r or r[5:7] != [0x08, 0x00]:
            return None
        d = unpack7(r[9:])                    # 13 00 50 00, then the name
        return d[4:20].split(b"\0")[0].decode("latin-1")

    def push_script(self, slot, code):
        b = code.encode()
        if len(b) > SCRIPT_BYTES:
            sys.exit(f"script is {len(b)} bytes; the device holds {SCRIPT_BYTES}")
        r = self.request(upload_msg(0x04, slot, 0, b.ljust(SCRIPT_BYTES, b"\0")), timeout=5)
        return r == ACK


def load_code(path):
    if path.endswith(".oxie16"):
        return json.load(open(path, encoding="utf-8"))["code"]["code"]
    return make_scene.rename_locals(make_scene.minify(open(path, encoding="utf-8").read()))


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ("list", "version", "push") or (args[0] == "push" and len(args) != 3):
        sys.exit(__doc__)
    e = E16()
    if args[0] == "version":
        print(e.version() or "no reply")
    elif args[0] == "list":
        for s in range(16):
            print(f"{s + 1:2}  {e.scene_name(s) or '(no reply)'}")
    else:
        slot = int(args[1])
        if not 1 <= slot <= 16:
            sys.exit("SLOT is 1-16")
        code = load_code(args[2])
        name = e.scene_name(slot - 1)
        ok = e.push_script(slot - 1, code)
        print(f"{'ok' if ok else 'FAILED (no ACK)'}: {len(code.encode())} bytes -> slot {slot} ({name})")
        if len(code.encode()) > 7000:
            print("warning: over 7000 bytes, the largest size tested on firmware 1.2")
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
