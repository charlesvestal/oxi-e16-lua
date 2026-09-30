# OXI E16 Lua scripting: field notes (firmware 1.2.0, API 1.3.0)

These notes supplement OXI's *Lua Scripting API Guide*, the official reference.
They record what the guide leaves out or gets wrong, as learned while building
`euclid.lua`. Most were found on firmware 1.2.0. OXI's guide for **API v1.3.0** (29 September
2026) adds a clock, push release and hold, MIDI note/CC input, a persistent store and a console
([below](#api-130-what-changed)). Items marked **[1.3]** come from that guide and haven't been
checked on hardware yet.

Source tags:
**[HW]** confirmed on hardware · **[FW]** found in the 1.2.0 firmware image (disassembly) ·
**[GUIDE]** OXI's API guide · **[1.3]** OXI's API 1.3.0 guide, not yet checked on hardware ·
**[EX]** header notes in the example `step_sequencer.e16script` ·
**[MODEL]** measured with `test/e16host.c` · **[?]** precaution, not verified

## API 1.3.0: what changed

- **Clock** **[1.3]**:
  - `clock.listen(true, res)` delivers `clock.onPulse(boundary, position, source)`, plus
    `onStart`, `onStop` and `onContinue(source)`. `res` must be 4, 8, 16, 32 or 96 (anything else
    means 16). Only resolution 96 (24 ticks per quarter note) gives triplet steps in whole ticks.
  - Sources: 0 = external MIDI transport, 1 = internal clock started by the firmware (alt action
    or recorder), 2 = internal clock started by Lua.
  - `clock.startInternal()`, `clock.stopInternal()` and `clock.setInternalBpm(20–300)` control
    the one internal clock that the Internal Clock alt action also uses. `clock.getBpm()` returns
    1 while no clock runs. `clock.getPosition(res)` gives the position.
  - Pulses arrive only while transport runs; external ticks without Start don't produce them.
  - Loading a script turns listening off and stops an internal clock that Lua started.
  - A clock callback error ends only that call; listening continues.
  - External Stop also stops a Lua-started internal clock. External Start and Continue don't
    replace a running internal clock.
  - Lua can't choose the MIDI clock output. It's whatever the alt action last used (Off at first).
  - The scripts here keep their own `run` flag, so Play/Stop can silence a sequence while external
    transport keeps running. They set that state right after `startInternal` rather than waiting
    for `onStart`, so a quick second press still stops.
- **Pushes** **[1.3]**:
  - `onEncoderPress` fires when the encoder goes down. `onEncoderRelease` follows exactly once,
    with `held_ms`; its `id` and `page` are the ones from the press.
  - `onEncoderHold` fires once per press after `controller.setHoldTime(30–3000 ms)`. It's off
    until armed, and loading a script disarms it.
  - On 1.2.0, `chords.lua` found that pushes arrived on release. **[HW]**
- **MIDI in** **[1.3]**: `midi.listen{notes=, cc=, channel=, port=}`, then `midi.onNote(port, ch, note, vel)`
  (Note Off arrives as velocity 0) and `midi.onCC`. An error in them stops listening.
- **Store** **[1.3]**: `store.data`, 1 KiB per scene (or `store.use("shared")` at top level), saved
  on scene exit. It's a candidate to replace packed variables, but it isn't editable from the
  device menu, and loaded tables cost heap.
- **Console** **[1.3]**: the OXI App's Scripts tab shows `print` output and Lua errors, including
  load errors. Open it before loading.
- `system.setUpdateRate` accepts **5–1000 ms** **[1.3]**. The uploaded script (after the app's
  minifier) can be up to **8,192 bytes** **[1.3]**.
- Manual controls get every turn, even at the ends of the range, with `increment` still showing
  the direction **[1.3]**. That may make the end-stop write-back below unnecessary.
- `controller.get(id, key)` reads a destination's properties **[1.3]**.
- **The load limit on 1.3.0 is a little lower than on 1.2.0.** TB-3PO failed to load at a 64-bit
  `e16host` load peak of 43,968 B, while LFO loads at 43,840 B. **[HW]** (The same TB-3PO had loaded
  at 43,920 B earlier.) A failed load looks like the scene's default header ("TB-3PO-Acid") and
  plain labels, and `onInit` never runs. Constant tables of strings are the cheapest thing to cut:
  one fixed-width string read with `sub` saved about 1.2 KB in TB-3PO and 0.9 KB in LFO.

## Environment

- Lua 5.4 with **32-bit floats** as `lua_Number`. Numeric API arguments are
  converted with float-to-int instructions. **[FW]**
- The only libraries are **base, math, string and table**. There's no `os`, `io`, `coroutine`,
  `utf8` or `debug`, so **there is no clock or time function**. **[FW]**
- `collectgarbage` works, and the GC runs in **generational** mode (`lua_gc(L, LUA_GCGEN)` at startup). **[FW]**
- On 1.2.0, `print` exists, but **the Lua Debug view isn't offered** in the Hold Mode menu
  (the options are Off / Looper / Off), even though "Lua Debug" is in the firmware's strings.
  **Script errors can't be seen on the device.** **[HW] [FW]** On 1.3.0 the OXI App's console
  shows them. **[1.3]**
- On 1.2.0 there are exactly **six callbacks**: `page.onInit`, `page.onPageChange`, `page.onVarChange`,
  `controller.onEncoderTurn`, `controller.onEncoderPress` and `controller.onSysex`.
  There's **no MIDI clock, transport, note or CC input**. The E16 receives clock itself
  (its looper syncs to it), but none of it reaches Lua. **[FW]** API 1.3.0 adds clock, release,
  hold and note/CC input (above).

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

## Timing: `system.update`

- The 1.2 guide leaves it out, but it exists and works. The 1.3 guide documents it. **[FW] [HW] [EX] [1.3]**
  - `system.setUpdateRate(ms)`: on 1.2.0, `ms` must be 20–1000 (5–1000 on 1.3.0). Anything else stores 0, which **disables** updates.
  - The firmware looks up the global `system.update` and calls it with **no arguments**,
    once **more than** `ms` has passed. SysTick runs at 10 kHz, so the real period is at least `ms + 0.1`,
    plus main-loop latency.
  - **If `update` raises an error, the firmware silently disables updates** (rate → 0).
    Clamp everything you read.
- On 1.2.0 it's the only timebase, so a sequencer can only free-run. (On 1.3.0 the scripts here
  step on `clock.onPulse` instead.) Two approaches for free-running:
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
  **`leds.updateByIndex(index, value, color)`**, which takes priority there. **[HW]** The 1.3
  guide says ID-based values now show in the normal view and follow page changes, which is
  worth retesting. **[1.3]**
- Index overrides are per physical ring and persist across pages. Reset them with `leds.reset(i)` when
  leaving your page, and redraw on return. **[GUIDE] [HW]**
- `color` is an **index into the OXI App's 100-color palette** (its 10×10 encoder color picker,
  read left to right, top to bottom, from 0), not a hue rotation as the guide calls it. It's absolute:
  the scene's encoder colors don't shift it. For example, 6 = dark blue, 18 = light blue, 34 = white, 50 = pink.
  **[HW]**
- `value` is 0–16383, and floats are floored. There's a batch form: `leds.updateByIndex({{i, v, c}, …})`. **[GUIDE]**

## Screen (from `glyphs.lua`)

- Lua has no drawing API. What it can reach is the title plus the 16 slot labels, shown as a **4×4 grid
  of up to 4 characters each** (rows are encoders 1–4, 5–8, 9–12, 13–16), with gaps between columns.
  In this view no value line appears under the labels. **[HW]**
- The font is **proportional** (`iiii` is much narrower than `MMMM`). Spaces are kept, and the whole
  label is **centered** as a block: `#   ` puts the `#` at the left of its slot, `   #` at the right. **[HW]**
- Widths against `#` (Width screen): `= + / \ _ o` and icon 135 (■) are **the same width as `#`**. A space is
  about ⅔ of that (3 spaces ≈ 2 `#`), `:` is narrow, and the blank codes 146, 154 and 156 have
  **zero width**. There's no full-width blank, so a label only keeps its columns in place if it is all
  same-width glyphs or all spaces. **[HW]**
- ASCII 32–126 all draw (`{` looks like `(`). Codes 128–153 are firmware icons, and **154–255 draw
  nothing**: **[HW]**

  | Code | Glyph | Code | Glyph | Code | Glyph |
  |---|---|---|---|---|---|
  | 128 | → | 137 | ⏪ | 146 | (blank) |
  | 129 | ← | 138 | ⏮ | 147 | small * |
  | 130 | ↑ | 139 | ⏭ | 148 | ' |
  | 131 | ↓ | 140 | ▸ | 149 | " |
  | 132 | ⊘ | 141 | ◂ | 150 | ° |
  | 133 | ▶ | 142 | lock | 151 | tall ‖ |
  | 134 | ⏸ | 143 | unlock | 152 | lock (alt) |
  | 135 | ■ | 144 | ┌ | 153 | die |
  | 136 | ⏩ | 145 | ┐ | | |
- Rewriting every label at a **20 ms** tick (50 per second) animates smoothly. **[HW]**

## Labels and title

- **The E16 font has icons at codes 128–153** (write them as `"\133"` escapes in Lua). **[HW]**
  128–131 → ← ↑ ↓ · 132 ⊘ · 133 ▶ play · 134 ❚❚ pause · 135 ■ stop · 136 ⏩ · 137 ⏪ ·
  138 ⏮ · 139 ⏭ · 140 ▸ · 141 ◂ · 142 lock · 143 open lock · 144–151 small corner and tick
  marks · 152 lock · 153 die. 154 and up are blank. Each counts as one of a label's 4
  characters, and they work in the header too.

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
- `midi.sendSysex` takes at most 128 bytes, including F0/F7. On 1.2.0, `onSysex` is the only MIDI input. **[GUIDE]**

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
- **A whole scene can be uploaded without the app** (`e16push.py scene`). The encoding below
  reproduces the OXI App 1.3's upload byte for byte for two captured scenes, and the device accepts
  it. **[HW]** (Captured by loading a CoreMIDI-logging dylib into an ad-hoc re-signed copy of the
  app. Launch it directly, not via `nohup`, which strips `DYLD_*`. The app also prints small
  sends to stdout.)
- **Header body (80 bytes):** title (16, NUL-padded), icon bitmap (32; the scene JSON holds it
  as a list, or the name `list32`), color, transmitMode, pcOnEntry, bankOnEntry (u16 BE),
  recentPage, recentPreset, transmitOnSceneEntry, transmitOnPageSwitch, transmitOnPresetLoad,
  smartTransmit, outputOnEntry, holdMode, acceleration, then the script name (18). The captures had
  zeros in most of these, so the order of the zero fields is assumed from the JSON.
- **Page body (976 bytes):** title (12), 0, channel, output, 0, then 16 encoders of 60 bytes each:
  name (8), abbr (4), color, the push action (instrument, parameter, type, display, mode, channel,
  lower u16, upper u16, nr1, nr2, output, scriptId: 14 bytes), two turn actions (the same fields
  plus defaultValue u16 after upper: 16 bytes each), and color2. u16 values are big-endian.
- **Packed data:** `total length` (u32 big-endian, body + 8), `11`, `body length` (u16 big-endian), `00`, the body,
  then a CRC (u32 big-endian). Everything is converted to 7-bit form: each 7 bytes become a byte of
  high bits (bit *j* = byte *j*) followed by the 7 low-7-bit bytes.
- **CRC:** the STM32 hardware CRC-32 of the body: poly `0x04C11DB7`, init `0xFFFFFFFF`, 32-bit
  little-endian words (zero-padded), no reflection, no final XOR. It matched every captured message.
