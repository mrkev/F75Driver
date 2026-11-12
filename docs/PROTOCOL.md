# AULA F75 configuration protocol

What is known about how the EPOMAKER x AULA F75 is configured over USB HID,
how each fact was established, and what is still open.

Every statement here carries one of three levels of confidence:

- **Verified**: observed on a real F75 (model ID `03 00 00 00 00 CD`) with this app.
- **Vendor**: read from the vendor's online driver, not yet exercised by this app.
- **Reference**: taken from the aula-f75-mac-driver project, which reports testing on a real F75.

All numbers are hexadecimal unless they are obviously counts or percentages.

## Sources

- **Vendor online driver**: <https://aulaiso.aulastar.com/>. A WebHID
  single-page app. Its main script is the `app-*.js` file referenced by the
  page (the hash in the name changes between releases). The protocol calls
  this keyboard family `kb_by_v2`. Useful search terms inside the script:
  `set_basic_info`, `get_basic_info`, `get_battery`, `send_batch`, `crc_sum`,
  `AULA_F75`, `mode_code`, `sleep_options`. The wired controller class uses
  `sendFeatureReport`; the wireless one uses `sendReport` and `oninputreport`.
  The script is not kept in this repository. Download it again when needed.
- **aula-f75-mac-driver**: <https://github.com/Itzadetunji/aula-f75-mac-driver>.
  An Electron app with a Swift helper. It has no licence file, so read it
  for facts only and copy nothing. Its `native/f75-helper/Sources/f75-helper/F75Protocol.swift`
  and `src/shared/onboard.ts` are the most useful files.

## Devices

| Connection | Vendor ID | Product ID | Product string | Config interface |
|---|---|---|---|---|
| USB cable | 258A | 010C | Gaming Keyboard | The interface whose max feature report size is 520 (usage page 1, usage 80) |
| 2.4 GHz dongle | 3554 | FA09 | 2.4G Wireless Receiver | Usage page FF02, usage 2; input 21, output 20, feature 8 bytes |

Verified:

- The keyboard has a mode switch. It only enumerates as the cable device
  when the switch is on USB. On 2.4G with the cable plugged in, the cable
  only charges it.
- macOS requires Input Monitoring permission to open either interface.
  Opening without it returns `kIOReturnNotPermitted` (E00002E2).
- A sleeping keyboard does not answer over the dongle. It sleeps after the
  stored sleep timer, which can be as short as one minute.

## Cable transport

One feature report, ID `06`, 520 bytes including the ID byte.

- **Request**: `06`, then a 7-byte header, then zero padding (or data for a write).
- **Reply**: send the request with Set Report, wait about 30 ms, then Get
  Report on ID `06`. The reply is `06`, a 7-byte header whose first byte
  echoes the command, then the payload from offset 8.
- The firmware returns stale or empty reports while busy. Check that byte 1
  echoes the command and retry if not. This app retries up to 4 times.

Header layout: `command, argument, 00, 01, 00, length low, length high`.
Read commands have the top bit set; the matching write is the same value
without it.

| Purpose | Read header | Write header | Payload | Status |
|---|---|---|---|---|
| Model ID | `82 01 00 01 00 06 00` | none | 6 bytes | Verified (read) |
| Key map, per layer | `83 LL 00 01 00 F8 01` | `03 LL 00 01 00 F8 01` | 504 bytes, ends `5A A5` | Vendor |
| Settings page | `84 00 00 01 00 80 00` | `04 00 00 01 00 80 00` | 128 bytes, ends `5A A5` | Verified (read and write) |
| Macros | none | `05 00 00 NN II LL HH` | chunks of up to 512 bytes | Vendor |
| Custom per-key colours | `86 00 00 01 00 80 01` | `06 00 00 01 00 80 01` | 3 × 126 bytes | Vendor |
| Battery | `87 00 00 01 00 02 00` | none | 2 bytes | Verified (read) |
| Effect colours | `8A 00 00 01 00 80 02` | `0A 00 00 01 00 00 02` | RGB triples | Vendor |
| Factory reset | none | `11 TT 00 01 00 01 00` | none | Vendor, never send casually |
| Direct LED frame | none | `08 00 00 01 00 7A 01` | 126 RGB triples | Reference |

`LL` is the layer. For macros `NN` is the chunk count, `II` the chunk
index, and `LL HH` the chunk length.

Vendor details not yet used:

- **Key map**: 4 bytes per key at `(position - 1)`. A normal key is a 32-bit
  code, big-endian. A macro key is `03, type, count, macro index` where type
  is 2 (once per press), 1 (loop) or 4 (repeat N times). The vendor waits
  100 ms after the write, then sends the macros.
- **Macros**: a table of 4-byte entries (offset low, offset high, length
  low, length high), followed by each macro as a length-prefixed UTF-8 name
  and 4 bytes per event: `(up or down flag & F0) | (duration bits 16..19)`,
  duration high, duration low, key value.
- **Custom per-key colours**: three planes of 126 bytes: red at
  `light_pos - 1`, green at `+126`, blue at `+252`, counted in the vendor's
  payload indexing (subtract 7 for an offset into the payload proper).
- **Effect colours**: starts from a default table in the vendor script, with
  an RGB triple per effect at that effect's `offset_color`.
- **Direct LED frame** (Reference): host-driven colours. The keyboard falls
  back to its stored effect if frames stop for about a second.

## Dongle transport

Output report ID `13`, 20 bytes including the ID. The 19 bytes after the ID are:

`command, packet count, packet index, length, data × 14, checksum`

- **Checksum**: `(13 + sum of the 18 bytes before it) mod 256`.
- **Replies** arrive as input reports with the same layout. The payload is
  the data of every packet in index order, each taken from byte 4 up to but
  not including the last byte.
- **Timing**: the vendor resends a request up to 5 times with a 3 second
  timeout. This app tries 3 times, waiting up to 1 second each.

| Purpose | Request (after the ID) | Reply packets | Status |
|---|---|---|---|
| Model ID | `05 01 00 00` | 1 | Verified |
| Settings page | `44 01 00 10` | 10 | Verified |
| Battery | `4A 00 00 00` | 1 | Verified |
| Key map | `41 01 00 00` | 36 | Vendor |
| Custom per-key colours | `42 01 00 00` | 27 | Vendor |
| Effect colours | `49 01 00 10` | 35 | Vendor |

For the key map, the layer is added to the fourth byte shifted left by 4
(`41 01 00 L0`).

**Online events** (Verified): an unsolicited packet whose first byte is `0A`
and fifth byte is `02` reports the radio link; the sixth byte is 1 when the
keyboard is online.

**Writes** (Vendor, never sent by this app): the data is split into 14-byte
chunks and each is sent as `command, chunk count, chunk index,
length | (extra << 4), data, checksum`. The keyboard echoes each packet and
the vendor resends a chunk up to 10 times until the echo matches. Commands:
`01` key map (extra = layer), `02` custom colours, `03` macros (extra =
chunk index), `04` settings page, `09` effect colours, `06` factory reset.

The aula-f75-mac-driver project reports that writing settings over the
dongle bricked an F75. Treat every dongle write as unsafe until someone
proves otherwise on hardware they are prepared to lose.

## Model IDs

| Model | ID |
|---|---|
| AULA F75 | `03 00 00 00 00 CD` (Verified) |
| AULA F75 (second variant) | `03 00 00 00 03 5C` |
| AULA F99 | `03 00 00 00 00 A4` |
| AULA F87 | `03 00 00 00 01 0B` |

## Battery reply

Two bytes: level in percent, then a status byte.

| Status | Observed when | Shown as |
|---|---|---|
| `10` | Cable plugged in, 99% | Charging |
| `11` | Cable plugged in, 100% | Plugged in, not charging |
| `01` | Cable unplugged, 100% | On battery |

Verified readings, interpreted by this app as: bit 4 set while the cable
supplies power, bit 0 clear only while the battery is filling. The vendor
script stores this byte without interpreting it. "Charging" rests on a
single observation.

## Settings page

128 bytes. The same layout is returned over cable and dongle (Verified).

| Offset | Meaning | Status |
|---|---|---|
| 0 | Mac layout when 1 | Vendor; read as 0 on the test keyboard |
| 1 | Polling rate: 1 = 250 Hz, 2 = 500 Hz, 3 = 1000 Hz | Verified for 3 |
| 2 | Constant 3 | Verified |
| 3 | Low latency: vendor writes 3 for on, 1 for off | Open, see below |
| 6, 7, 8 | Constants 4, 4, 7 | Verified |
| 9, 10 | Lighting effect, big-endian | Verified for 0 and 1 |
| 11, 12 | Constants 20, 01 | Verified |
| 14 | 0 over the cable, 1 over the dongle | Verified, see below |
| 15 | Win lock when 1 | Vendor |
| 24 | Sleep timer in 30-second units, 0 = never | Verified for 2 (1 minute) |
| 56, 57 | Vendor writes FF FF; the test keyboard holds 00 8F | Open |
| 58–125 | Effect table: 34 entries of 2 bytes | Verified for effect 1 |
| 126, 127 | Signature `5A A5` | Verified |

**Effect table**: entry for effect *n* (1-based) is at `58 + (n - 1) × 2`.
The first byte is brightness, the second is `(speed << 4) | colour`.

- Brightness 0–9 (Reference; 9 and 5 Verified as stored and visibly
  different). The vendor UI caps the F75 at 4, yet the test keyboard had 9
  stored for most effects from the factory.
- Speed 0–4 (Reference).
- Colour is a palette index; 7 means the firmware cycles colours itself.

**Lighting effects**: 0 Off, 1 Fixed on, 2 Respire, 3 Rainbow, 4 Flash
away, 5 Raindrops, 6 Rainbow wheel, 7 Ripples shining, 8 Stars twinkle,
9 Shadow disappear, 10 Retro snake, 11 Neon stream, 12 Reaction, 13 Sine
wave, 14 Retinue scanning, 15 Rotating windmill, 16 Colorful waterfall,
17 Blossoming, 18 Rotating storm.

- Effects 6 and 14 stay dark on the F75 (Reference). This app does not offer them.
- The vendor script uses 277 (`01 15`) for custom per-key lighting. The
  reference project uses 21 for "self-define". Unresolved; this app labels
  277 "Custom" and does not let you select either.
- Byte 9 is described by the reference project as a per-key flag that may
  only be cleared. This app writes 0 to it on every lighting change.

**Sleep values**: the vendor offers 1, 2, 3, 4, 6, 10, 20, 30, 40, 60 and
120 (30 seconds to 60 minutes), plus 0 for never. The reference project
restricts writes to 0, 2, 3, 4, 6, 8, 10, 20, 30 and 40.

### How this app writes the page

Cable only. Implemented in `KeyboardMonitor.setLighting` and
`F75Protocol.wiredSettingsWrite`:

1. Read the page and require the `5A A5` signature.
2. Copy it and change only bytes 9, 10 and the one effect-table entry.
3. Refuse to build the report if any byte outside 9, 10 and 58–125 differs.
4. Send `06 04 00 00 01 00 80 00` followed by the 128 bytes, zero-padded to 520.
5. Wait 150 ms, read the page back and require it to equal what was sent.

This deliberately does not rebuild the page from constants the way the
vendor does, because the test keyboard holds values the vendor never
writes (byte 3 = 2, bytes 56–57 = `00 8F`).

Verified on hardware: four writes (effect 0 → 1, brightness 9 → 5 → 9,
effect 1 → 0), each read back correctly, with the backlight visibly
turning on. Other effects and the speed nibble use the same path but have
not been tried.

## Open questions

- **Byte 3 (low latency)**: the keyboard reports 2, which the vendor never
  writes. The app shows "Off" because it is not 3.
- **Byte 14**: 0 over the cable and 1 over the dongle. The vendor's dongle
  write sets it to 1 and its cable write leaves it 0, so it likely marks
  the connection. Never copy a page read over one transport to the other.
- **Bytes 56–57**: `00 8F` on the keyboard, `FF FF` in the vendor's writes.
- **Brightness range**: 9 works, but the vendor UI says 4.
- **Custom lighting effect code**: 277 or 21.
- **Battery status**: "charging" seen once; other bits unknown.
- **Mac layout and Win lock**: never seen set on the test keyboard.
