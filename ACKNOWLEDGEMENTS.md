# Acknowledgements

F75 Driver contains no third-party source code. Its knowledge of how the
AULA F75 communicates comes from studying the following, and it would not
exist without them.

## AULA online driver

<https://aulaiso.aulastar.com/>

The vendor's web-based configuration tool. Its WebHID code was read to learn
the keyboard's protocol for interoperability: device IDs, report IDs and
lengths, the read-request byte sequences for the cable and the 2.4 GHz
dongle, the dongle packet framing and checksum, the model identifier table,
and the layout of the settings page (polling rate, sleep timer, lighting
effect table and so on). No code or assets from it are included.

## aula-f75-mac-driver by Itzadetunji

<https://github.com/Itzadetunji/aula-f75-mac-driver>

An Electron-based macOS driver for the same keyboard, with a Swift helper.
It was used as a reference for which IOKit HID calls reach the keyboard, for
the practice of retrying reads until the settings page carries its `5A A5`
signature, and for the English names of the onboard lighting effects. At the
time of writing the repository has no licence file, so none of its code was
copied; the implementation here is written from scratch.

That project in turn credits OpenRGB's `SinowealthKeyboard10cController`
for documenting the Sinowealth `258A:010C` protocol.

---

This is an independent project. It is not affiliated with or endorsed by
AULA or EPOMAKER.
