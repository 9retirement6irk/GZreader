The **House** tab shows your [Home Assistant](https://www.home-assistant.io)
rooms with their lights, switches, thermostats, locks, garage doors and
scenes, so you can switch things from the Kindle. GZreader talks to Home
Assistant directly over your Wi‑Fi (its REST API): there's no web page or
browser involved, and nothing goes through anyone else's server.

Not on the Kindle 2 and DX: they have no Wi‑Fi.

## Turning it on

1. **Settings → Connections → Home Assistant (House)**, and connect (below).
2. Tick **House tab** there. The tab goes at the end of the tab bar; move it
   or turn it off in **Settings → Interface → Navbar → Tabs** like any other
   tab. The bar holds 7 tabs: if it's full, turn one off first.

## Connecting

You need Home Assistant's address and a **long-lived access token**: in Home
Assistant open your profile (bottom left) → **Security** → **Long-lived access
tokens** → **Create token**, and copy it (Home Assistant shows it only once).

- **Connect with QR code**: the [setup page](Setup-Page-and-Connections) opens
  at its House tab; paste the address and the token on your phone.
- **Find Home Assistant on this Wi‑Fi**: the Kindle looks for Home Assistant's
  announcement on the network for a few seconds and fills in its address;
  then paste or type the token.
- **Connect by typing**: both on the Kindle's keyboard.

The address is the one you open Home Assistant with at home, e.g.
`homeassistant.local:8123` or `192.168.1.20:8123` (`:8123` is added when you
type no port). A Home Assistant Cloud or other `https://` address works too.

**Rooms** come from Home Assistant's areas, which only an **administrator's**
token can read. With another user's token the tab still works, grouped by kind
(Lights, Switches, Climate, Locks…) instead, and says why.

## What the tab shows

```
Refresh                       updated 1 min ago
Living room
  Ceiling light               On · 80%      ›
  Floor lamp                  Off      [toggle]
  Thermostat                  20.5° → 21°   ›
  Temperature                 20.5°
Outside
  Front door                  Locked        ›
  Garage door                 Closed        ›
Scenes
  Goodnight                                 ›
```

Each room (area) in Home Assistant's order, then **Other** (switchable things
in no room) and **Scenes**. A device's name loses its room's name in front
("Living room Ceiling light" → "Ceiling light"). Shown: lights, switches,
fans, helpers (input booleans), thermostats, locks, covers (garage doors,
blinds), scripts and scenes, plus temperature and humidity sensors and
door and window sensors. Devices hidden in Home Assistant aren't shown.

What tapping (or the device's letter key) does:

- **Switch, fan, plain light**: on or off.
- **Dimmable light**: a dimmer with **On**, **Off**, **− 10%** / **+ 10%**
  (it stays open for another step) and **10% / 40% / 80% / 100%**. Steps
  instead of a slider: each press is one change and one screen refresh.
- **Thermostat**: the temperature now and the target, a step down or up.
- **Lock**: unlocks (asks first) or locks.
- **Garage door, gate**: opens (asks first) or closes; blinds open and close
  without asking.
- **Scene, script**: runs it.
- **Sensors**: show their value only.

**Refresh** (the first row) fetches everything again. The list also refreshes
every 30 seconds while the tab is on the screen, and Wi‑Fi stays on while it's
open (in Auto it goes off a minute after you leave). The last list is kept on
the Kindle, so the tab opens at once with it and then updates. If Home
Assistant can't be reached, the last list stays with a line saying why.

## Settings

**Settings → Connections → Home Assistant (House)**:

- **House tab**: in the tab bar or not.
- **Rooms and devices**: hide a room, or single devices in it (e.g. a
  Zigbee bulb's "child lock" switch). Open the House tab once first so the
  Kindle knows your rooms.
- **Ask before unlocking or opening** (on): locks, garage doors, gates and
  doors ask before they're unlocked or opened.
- **Disconnect**: removes the address and token from the Kindle. The token
  still works until you delete it in Home Assistant (your profile →
  Security).

## Privacy

The token is kept in GZreader's settings on the Kindle, like the Memos token,
and never written to the log. The log names Home Assistant's address, what
was switched (e.g. `light.turn_on light.porch`) and when, nothing else. The
tab asks Home Assistant only for what it shows: one small request rendered by
Home Assistant's templates (with a token that isn't an administrator's, Home
Assistant's whole list of states, which is bigger).
