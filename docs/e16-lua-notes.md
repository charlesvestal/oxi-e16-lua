# OXI E16 Lua scripting: field notes (firmware 1.2.0)

These notes supplement OXI's *Lua Scripting API Guide v1.2.0*, the official reference.
They record what the guide leaves out or gets wrong, as learned while building
`euclid.lua`.

Source tags:
**[HW]** confirmed on hardware · **[FW]** found in the 1.2.0 firmware image (disassembly) ·
**[GUIDE]** OXI's API guide · **[EX]** header notes in the example `step_sequencer.e16script` ·
**[MODEL]** measured with `test/e16host.c` · **[?]** precaution, not verified

## Environment

- Lua 5.4 with **32-bit floats** as `lua_Number`. Numeric API arguments are
  converted with float-to-int instructions. **[FW]**
- The only libraries are **base, math, string and table**. There's no `os`, `io`, `coroutine`,
  `utf8` or `debug`, so **there is no clock or time function**. **[FW]**
- `collectgarbage` works, and the GC runs in **generational** mode (`lua_gc(L, LUA_GCGEN)` at startup). **[FW]**
- `print` exists, but **the Lua Debug view isn't offered** in the Hold Mode menu
  (the options are Off / Looper / Off), even though "Lua Debug" is in the firmware's strings.
  **Script errors can't be seen on the device.** **[HW] [FW]**
- There are exactly **six callbacks**: `page.onInit`, `page.onPageChange`, `page.onVarChange`,
  `controller.onEncoderTurn`, `controller.onEncoderPress` and `controller.onSysex`.
  There's **no MIDI clock, transport, note or CC input**. The E16 receives clock itself
  (its looper syncs to it), but none of it reaches Lua. **[FW]**

## Memory and size (the main constraint)

- The heap is FreeRTOS `heap_4`: a **48 KB pool** shared with the firmware,
  with 8-byte block headers and 8-byte alignment. **[FW]** An OXI dev said Lua gets about 40 KB; the probe
  measures a bit more (below).
- The VM, libraries and API tables take about **12 KB** before any script loads. **[MODEL]**
- **Euclid reads 30 KB** on the device (`collectgarbage("count")`, which excludes allocator
  overhead). **[HW]**
- **Measured ceiling: `probe.lua` freezes at a Lua count of 42.3 KB.** **[HW]** Running the same probe
  in `e16host` with a heap cap puts that at a **total budget of about 46.6 KB in model terms**
  (VM + libraries + API + script, allocator overhead included). **[MODEL]** That's the ceiling for
  memory while *running*; loading has a lower one (below).
- **Loading is the real limit: a modeled load peak of about 42.6 KB.** Loading (compiling) needs large
  unbroken blocks and holds the source text and parser memory as well, so it runs out below the
  running ceiling. Load probes (`tools/make_load_probes.py`: dummy code of known size) load at
  **42.6 KB** and fail at **43.5 KB** of modeled load peak. **[HW] [MODEL]**
- **Rules:** `e16host`'s load peak plus the 11.9 KB base must stay **≤ 42.5 KB**, and its playing peak plus
  the base **≤ 46.6 KB**. The example step sequencer (load peak 43.6 KB) fails to load, exactly as
  predicted. A diagnostic copy never ran its first line. **[HW]**
- The upvalue limit is standard Lua's 255, not ~35 as the example claims; that claim was
  probably a misread memory failure. **[FW]** **Rule of thumb: keep ≥ 3 KB of modeled headroom and
  code ≤ ~6 KB.** TB-3PO (old) runs with 5.1 KB of headroom. **[HW] [MODEL]**
- **Float formatting prints nothing on the device** (likely newlib-nano printf without float
  support). A probe that formatted `%.1f` showed a static header; with whole-number formatting it
  works. Avoid `%f`/`%g` in `string.format`, and avoid `tostring`/`..` on floats; format tenths
  by hand (`x // 10 .. "." .. x % 10`). **[HW]** (Inferred from one symptom; not yet isolated.)
- The scene's `code` field is exactly what gets uploaded. Minifying it (comments, whitespace,
  short names for file-level locals) cut the scripts here by 20–25%. **[HW]**
- **If a script doesn't load, it fails silently.** The scene shows its default title
  (e.g. `Step seq-P.1`) and default labels, and nothing responds. That's what the example step
  sequencer does (cause not isolated; see above). **[HW]**
- Scripts are uploaded as source (minified by the app) and **compiled on the device**, so
  debug info (line numbers, local names) stays in RAM, and compiling needs a temporary peak on top. **[FW] [GUIDE]**
- **Size limit: at least 7,000 bytes on firmware 1.2.** Padded size probes of 6,100–7,000 bytes all load
  (`tools/make_size_probes.py`). **[HW]** The app caps scripts at 8,000. The example's note that the device
  rejects scripts over about 6,240 bytes may have applied to firmware 1.1. **[EX]** Its note of a limit of
  about 35 upvalues per function is untested. **[EX]**
- **Seeing errors without Lua Debug:** `tools/make_diag.py` makes a copy of a scene whose code starts by
  setting the header to "diag: ran" and ends with `tools/diag_wrap.lua`, which wraps every callback in
  `pcall` and prints any error across the 16 labels. If "diag: ran" never shows, the script failed
  before running: a compile error, or running out of memory while loading. **[MODEL]**
- What costs memory is mostly **bytecode, not data**: about 12 bytes per VM instruction including
  constants and debug info, and every function carries a fixed overhead. What helped:
  - table-driven code with few functions
  - no allocation per tick (no tables or `string.format` in `update`)
  - storing state in `var` (it lives outside the Lua heap)
  - checking the heap on the device: the Euclid header shows it at startup, and `probe.lua`
    finds the ceiling **[MODEL] [HW]**

## Timing: `system.update` (undocumented)

- The guide leaves it out, but it exists and works. **[FW] [HW] [EX]**
  - `system.setUpdateRate(ms)`: `ms` must be 20–1000. Anything else stores 0, which **disables** updates.
  - The firmware looks up the global `system.update` and calls it with **no arguments**,
    once **more than** `ms` has passed. SysTick runs at 10 kHz, so the real period is at least `ms + 0.1`,
    plus main-loop latency.
  - **If `update` raises an error, the firmware silently disables updates** (rate → 0).
    Clamp everything you read.
- It's the only timebase, so a sequencer can only free-run. Two approaches:
  - A **fixed 20 ms tick with a carried remainder** keeps the average tempo but adds up to 20 ms of lurch.
  - **Choosing a rate so each step is a whole number of ticks** gives even steps, with tempo
    within about 1%. Euclid and the example both use this. **[MODEL] [EX]**

## Encoders

- `onEncoderTurn` also fires with **`increment = 0`** for recorder, random and group value changes,
  and with **`id = 255`** for non-script controls. Filter both. **[GUIDE]**
- Manual mode: the saved scene doesn't seem to store the manual flag, so set it at runtime with
  `controller.set(id, {manual = true, v = 8192})`. **[?]** (Euclid does this, and it works. **[HW]**)
- Manual encoders can **lock at an end stop**. Write a mid-scale `v` (8192) back after each turn. **[EX]**
- `enc.is_held` is always false. `onEncoderPress` has no increment. **[GUIDE]**

## LED rings

- **`leds.update(id, …)` (by script ID) doesn't show in the normal encoder view.** It only appeared
  on the settings page. The normal view draws the control's own value instead. Use
  **`leds.updateByIndex(index, value, color)`**, which takes priority there. **[HW]**
- Index overrides are per physical ring and persist across pages. Reset them with `leds.reset(i)` when
  leaving your page, and redraw on return. **[GUIDE] [HW]**
- `color` is a **hue rotation, 0–100** (the manual says 0–15). 100 may equal 0 (a full turn), so the
  example's playhead color of 100 may be invisible. **[FW] [GUIDE] [?]**
- `value` is 0–16383, and floats are floored. There's a batch form: `leds.updateByIndex({{i, v, c}, …})`. **[GUIDE]**

## Labels and title

- `slots.update(i, text)` shows up to 4 characters, per physical slot, persisting across pages. Reset
  them when leaving your page. **[GUIDE] [HW]**
- During `onPageChange(prev, curr)`, don't rely on `controller.getPage()` to return `curr`. Pass `curr` through. **[?]**
- `page.setTitle` takes 15 characters. Calling it from a callback can **freeze the header**. The workaround:
  call `page.resetTitle()`, then set the new text on the next `update` tick. The firmware centers
  short titles (pad with spaces to keep them left-aligned). **[EX]**

## MIDI

- `midi.sendMidi(out, channel, status, d1, d2)`: the status byte already includes the channel. The firmware
  hardcodes USB-MIDI CIN 9 (note-on) in the packet header, which is fine for notes.
  `out` 0 means all ports. **[FW] [GUIDE]**
- `midi.sendCC(out, channel 0–15, cc, value)`. For a stop panic, send note-offs plus CC 123 and CC 120. **[GUIDE] [EX]**
- `midi.sendSysex` takes at most 128 bytes, including F0/F7. `onSysex` is the only MIDI input. **[GUIDE]**

## Variables (`var`)

- There are **32 slots per scene**, names up to 16 characters, stored as 32-bit values. Registrations beyond 32 are
  dropped. **[FW] [GUIDE]** The example keeps packed values below 2^24, possibly because of float precision. **[EX]**
- `var.set` only writes RAM (a name lookup plus a store). It's cheap enough to call on every edit. **[FW]**
- **Variables outlive script changes.** Names an older version registered keep occupying the 32
  slots, so a new version's registrations can silently fail and `var.get` returns nil, which errors
  out of `onInit` partway. Stamp a layout version (`ver`) and call `var.deleteAll()` when it
  doesn't match; guard reads with `or default`. **[MODEL]** (Suspected on hardware with TB-3PO.)
- `page.onVarChange` fires only for edits made in the device menu, never for `var.set`. **[GUIDE]**
- To edit vars on the device: hold an encoder and tap Shift to open the control editor, press
  Shift + encoder 3 for the Scene tab, then choose Script Variables. **[HW]**

## OXI App files

- The app's E16 folder is set under **Scenes → Assign PC/Mac folder**. It's stored as the bookmark
  `flutter.BookmarkType.e16Scenes` in the `com.oxiinstruments.oxiapp` defaults. It contains:
  - `Scripts/*.e16script`: plain Lua with CRLF line endings
  - `Scenes/*.oxie16`: JSON **[HW]**
- In a scene's JSON:
  - `code.code` is the minified script that's uploaded
  - `code.fullScript` is the full source, and `code.scriptName` names it in the library
  - `pages[p].encoders[i]`: `turn_actions[0]` with **`type` 11 = Script** and `scriptId`;
    `push_action` with **`type` 12 = Script** and `scriptId`; `type` 0 = off **[HW]**
- To upload: go to **Scenes**, click **Refresh Views**, and drag the scene from *On Computer* onto a
  slot under *On Device*. `tools/make_scene.py` generates a wired scene from a template. **[HW]**
- Script IDs 1–49 work for turns and pushes. **[HW]** The example uses push IDs 101–116; that's unverified,
  because its script never ran.
- Several destinations can share one script ID. **[GUIDE]** `chords.lua` reuses push IDs 17–32 on
  pages 1–11 and tells pages apart with `enc.page`. That's untested on hardware. **[?]**
- Data-heavy scripts: pack the data into one long-bracket string (`[=[...]=]`), with one byte per
  value offset into the printable range, and parse it with `string.byte`/`find` on demand. That
  avoids tables and escapes. The whole string counts toward the script's size, and compiling it
  raises the load-time memory peak. **[MODEL]**

## USB-MIDI SysEx protocol (what the OXI App sends)

Captured from OXI App uploads on firmware 1.2.0 by logging CoreMIDI in the app. `tools/e16push.py`
implements it. **[HW]**

- Every message starts `F0 00 21 5B 02 01`: OXI's manufacturer ID, then `02 01` for the E16.
- **Firmware version:** send `03 00`. Firmware 1.2.0 replies `03 00 03 01 02 0E 03 02 02 0E 03 00 00 00`
  (layout not decoded).
- **Read a slot's scene name:** send `07 00 <slot 0–15> 00 00 00 00 00 00`. The reply is `08 00 <slot> 00`
  plus packed data: `13 00 50 00`, the name (NUL-padded), and more fields.
- **Upload:** `08 <kind> <slot 0–15> <index>` plus packed data. The device answers each message with
  `08 53` (ACK). The app sends kind 0 (scene header, 80-byte body, starts with the name), then kind 1
  for pages 0–11 (976-byte body each), then kind 4 (script: the minified code padded with zeros to
  8192 bytes, in one ~9.4 KB SysEx message). It doesn't split anything into chunks.
- **A script can be uploaded on its own.** Kind 4 alone replaces the scene's code and leaves its pages
  and variables as they are. The new code runs when the scene is next opened. **[HW]**
- **Packed data:** `total length` (u32 big-endian, body + 8), `11`, `body length` (u16 big-endian), `00`, the body,
  then a CRC (u32 big-endian). Everything is converted to 7-bit form: each 7 bytes become a byte of
  high bits (bit *j* = byte *j*) followed by the 7 low-7-bit bytes.
- **CRC:** the STM32 hardware CRC-32 of the body: poly `0x04C11DB7`, init `0xFFFFFFFF`, 32-bit
  little-endian words (zero-padded), no reflection, no final XOR. It matched every captured message.
- The header and page bodies are only partly decoded (names, lengths). The encoder wiring inside
  the 976-byte page body isn't mapped yet.
