Installing: [Install on the Nook 1st Edition](Install-Nook-1st-Edition).

GZreader also runs on Barnes & Noble's first Nook (2009): a 6" e-ink page
with a small colour touchscreen under it. **This is a test build:** it runs
on a real Nook (firmware 1.0.0 with nookDevs' Softroot 2.5.1): the setup
guide, Home, the colour screen's controls, Wi‑Fi, downloading books,
updates over Wi‑Fi, and a GZreader icon in the Nook's app list. Try it on a
Nook you're prepared to restore, and send back what happens ([what to send](Install-Nook-1st-Edition#what-to-send-back)).

How it works: the Nook's processor is the same family as a Kindle 3's, but
its kernel has the floating-point unit switched off and stops programs that
read unaligned memory, so the Nook gets its own build of KOReader's programs
(`gzreader-nook-1st-edition-<version>.zip`: floating point in software, no
unaligned reads), plus what the Nook's Android 1.5 lacks (a Linux C library
and BusyBox, from Debian 7). A start script pauses the Nook's own software
while GZreader runs and resumes it when you exit. It also wakes what Android
had put to sleep: the colour screen, its touch panel and Wi‑Fi. Nothing on
the Nook's system is changed for good: the script's changes are undone by
exiting or restarting the Nook.

## Both screens

- **The e-ink page** shows GZreader as on a Kindle 4, refreshed the way
  Android does it, through the Nook's kernel: moving the selection, menus,
  the clock and other changes refresh just the part that changed, without
  a flash. A full refresh (with a flash, which clears the ghosting) comes
  when GZreader asks for one, as on a Kindle: every few page turns, and
  when a full-screen view opens or closes. After a tap or a button press
  GZreader waits until the screen has stopped changing (a fraction of a
  second) and refreshes once. Sending updates straight to the e-ink
  controller froze the Nook every time it was tried, so GZreader doesn't.
  If the screen doesn't keep up with what you do (a menu that doesn't
  appear until the next flash), go back to a full refresh every time
  (as up to 1.26.6) with `adb shell touch /data/gzreader/eink-flash` and
  start GZreader again; `adb shell rm /data/gzreader/eink-flash` undoes it.
- **The colour touchscreen** is what you drive it with, and it changes with
  what you're doing:
  - **Controls** (Home, menus, lists): ▲ ▼ ◀ ▶ and **OK** (the Kindle 4's
    5-way), **Back**, **Menu** (the quick panel), **Home**, ◀◀ ▶▶ (page back / forward) and **•••** (the next
    panel).
  - **Reading info** (in a book): title, chapter, page, a progress bar, the
    time, battery and Wi‑Fi. Or **Cover**: the book's cover with its title,
    author and progress. Touch it to get the controls for a while.
  - **Keyboard** (typing: search, Notes, connecting): letters, numbers and
    symbols on the colour screen, so the page isn't covered by an e-ink
    keyboard. **Done** swaps it for the controls (▲ ▼ to reach the dialog's
    buttons), the ⌨ button brings it back.
  - Swipe left or right on it to turn pages; up or down for its next panel.
- **The page buttons** on both sides turn pages; **n** (under the colour
  screen) is Home; **power** puts the Nook to sleep and wakes it.

**Settings → Interface → Colour screen** chooses what shows when: while
reading (reading info, cover, controls or nothing), elsewhere (controls,
clock or nothing), when typing (colour keyboard, or the e-ink keyboard with
the arrows), whether a touch brings up the controls and for how long, swipe
to turn pages, how long until it goes dark (a touch lights it again; the
first touch only lights it), its brightness, and a **touch test** with
mirror / swap switches in case the touch is the wrong way round on your
Nook.

Wi‑Fi: GZreader uses the networks saved in the Nook's own settings. When
Android has switched Wi‑Fi off (it does when its screen goes off), the start
script switches it on and connects as Android would, and switches it off
again when you exit GZreader. It also turns the Wi‑Fi chip's power saving
off while GZreader runs: with it on, the chip naps between packets, loses
some, and sign-ins time out. (`GZ_NOOK_WIFI=off` leaves Wi‑Fi alone.)

Not in the test build: audiobooks and read aloud (the Nook has a speaker,
but GZreader plays audio with the Kindle's player), and switching Wi‑Fi on
and off from GZreader's menus.
