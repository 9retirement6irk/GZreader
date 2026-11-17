Bluetooth on the Kindles that have it: turning it on and off, pairing
headphones and speakers, connecting to them.

**Which Kindles:** those with Bluetooth, on firmware 5.x — the Kindle 8th
generation and later, Oasis, Paperwhite 4 and newer, Scribe, Colorsoft. On
the Kindle 2, 3, DX, 4, Touch, the Paperwhites 2 and 3 and the Nooks there is
no Bluetooth row (they have no Bluetooth, or no way to manage it).

## Settings → General → Bluetooth

The row comes right after Wi‑Fi.

- **The tick** turns Bluetooth on or off. Turning it off disconnects what
  was connected first.
- **A tap on the row** opens **Bluetooth devices**. If Bluetooth is off it
  is turned on, then the Kindle searches for devices for about ten seconds
  ("Searching for devices…"). The list shows paired devices and the ones
  found nearby, with Connected, Paired or Available beside each.
- **A tap on a device** offers what can be done with it:
  - **Pair** — a device found nearby. Put it in pairing mode first
    (usually: hold its power or Bluetooth button until a light flashes).
  - **Connect** / **Disconnect** — a paired device.
  - **Forget** — unpair it (it asks first).
  - **Info** — its name, address, signal and status.

GZreader uses Amazon's own Bluetooth service (`com.lab126.btfd`), so devices
paired here are paired in Amazon's Settings too, and the other way round.
Like Amazon's own Settings, it pairs audio devices (headphones, speakers,
car adapters); a device that asks you to type or confirm a code may not
pair.

## What GZreader plays over it

Not yet: audiobooks, music and read aloud aren't offered on these Kindles
(they have no speaker or headphone jack; playing through Bluetooth is being
worked on).

The log (crash.log) has Bluetooth lines for power changes and device
counts; device names and addresses aren't written to it.
