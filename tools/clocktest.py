#!/usr/bin/env python3
"""Drive the E16 with external MIDI clock over USB and log what it sends back.

  clocktest.py [BPM]     Start, 4 s of clock, Stop, 1 s, Continue, 2 s, Stop

Open a clocked scene (Euclid, Mod Seq, TB-3PO or LFOx16) on the E16 first, with its
output port on All or USB. Prints note/CC timing per phase. Needs mido + python-rtmidi.
"""
import sys
import time

import mido


def port(names):
    return next(n for n in names if "E16" in n)


def main():
    bpm = float(sys.argv[1]) if len(sys.argv) > 1 else 120.0
    out = mido.open_output(port(mido.get_output_names()))
    inp = mido.open_input(port(mido.get_input_names()))
    tick = 60.0 / (bpm * 24)
    log = []                                   # (t, phase, msg)
    t0 = time.perf_counter()

    def drain(phase):
        for m in inp.iter_pending():
            if m.type in ("note_on", "note_off", "control_change"):
                log.append((time.perf_counter() - t0, phase, m))

    def run(phase, secs, clock=True):
        end = time.perf_counter() + secs
        nxt = time.perf_counter()
        while time.perf_counter() < end:
            now = time.perf_counter()
            if clock and now >= nxt:
                out.send(mido.Message("clock"))
                nxt += tick
            drain(phase)
            time.sleep(0.0005)

    for _ in inp.iter_pending():
        pass
    out.send(mido.Message("start")); run("start", 4.0)
    out.send(mido.Message("stop")); run("stopped", 1.0, clock=False)
    out.send(mido.Message("continue")); run("continue", 2.0)
    out.send(mido.Message("stop")); run("end", 0.5, clock=False)

    step = 60.0 / (bpm * 4)
    for phase in ("start", "stopped", "continue", "end"):
        ev = [(t, m) for t, p, m in log if p == phase]
        ons = [(t, m) for t, m in ev if m.type == "note_on" and m.velocity > 0]
        offs = [m for t, m in ev if m.type == "note_off" or (m.type == "note_on" and m.velocity == 0)]
        ccs = [m for t, m in ev if m.type == "control_change"]
        print(f"\n== {phase}: {len(ons)} note-ons, {len(offs)} note-offs, {len(ccs)} CCs")
        if ons:
            first = ons[0][0]
            steps = {}
            for t, m in ons:
                steps.setdefault(round((t - first) / step), []).append(m.note)
            print("  first note-on at %.3f s; steps from it (16ths at %g BPM):" % (first, bpm))
            print("  " + " ".join(f"{k}:{'/'.join(map(str, v))}" for k, v in sorted(steps.items())[:24]))
            ts = sorted({round((t - first) / step) * step + first for t, m in ons})
            err = [abs((t - first) / step - round((t - first) / step)) * step * 1000 for t, m in ons]
            print("  timing jitter vs the 16th grid: max %.1f ms" % max(err))
        if ccs:
            vals = {}
            for m in ccs:
                vals.setdefault((m.channel + 1, m.control), []).append(m.value)
            for k, v in vals.items():
                print(f"  ch{k[0]} CC{k[1]}: {len(v)} values, {v[:16]}")


if __name__ == "__main__":
    main()
