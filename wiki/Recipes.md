The **Recipes** tab shows the recipes of your [Mealie](https://mealie.io), a
recipe manager you host yourself: search them, pick a category, and read one
with its ingredients and steps while you cook. GZreader talks to Mealie
directly (its REST API): there's no web page or browser involved, and nothing
goes through anyone else's server.

It's an optional tab, off until you turn it on. Not on the Kindle 2 and DX:
they have no Wi‑Fi.

## Turning it on

1. **Settings → Accounts and services → Recipes**, and connect (below).
2. Tick **Recipes tab** there. The tab goes at the end of the tab bar; move it
   or turn it off in **Settings → Home and tabs → Tab bar → Tabs** like any other
   tab. The bar holds 7 tabs: if it's full, turn one off first.

## Connecting

There are two ways to sign in. Either way the Kindle keeps an **API token**,
never your password, and never writes the token to its log.

### With an API token

In Mealie open your profile (top right) → **API tokens**, give the token a
name and **Generate**, and copy it (Mealie shows it only once). Then:

- **Connect with QR code**: the [setup page](Setup-Page-and-Connections) opens
  at its Recipes tab; paste Mealie's address and the token on your phone.
- **Connect by typing**: both on the Kindle's keyboard.

### With single sign-on

For a Mealie that signs you in through an identity provider (OIDC: Authentik,
Authelia, Keycloak, Pocket ID…). A Kindle has no browser, so the sign-in
happens on your phone or computer:

1. **Connect with QR code**, and on the page's Recipes tab type Mealie's
   address, leave the token empty and press **Sign in with single sign-on**.
2. Sign in at your provider as usual. The browser comes back to the setup
   page, which says you're connected.

GZreader then asks Mealie for an API token of its own and keeps only that. It
is listed as **GZreader** in your Mealie profile → API tokens, where you can
delete it; **Disconnect** on the Kindle deletes it too when Mealie can be
reached.

What it needs:

- A Mealie new enough to sign apps in (its `/api/auth/oauth/native` endpoints).
  An older one says so on the page: update Mealie, or use an API token.
- The address the provider sends the browser back to must be **allowed as a
  redirect for Mealie's client** at your provider. The setup page shows it
  under *Single sign-on*; unless you changed it, it's GZreader's hand-off page,
  the same one Grimmory's single sign-on uses:

      https://9retirement6irk.github.io/GZreader/oauth2-callback

  ([how the hand-off page works, and hosting your own](Setup-Page-and-Connections)).
  If Mealie has a separate client for apps (`OIDC_NATIVE_CLIENT_ID`), allow it
  on that one.

### The address

The one you open Mealie with, e.g. `mealie.example.com` or
`192.168.1.30:9925`. With no `http://` or `https://` typed, an address on
your home network is tried over plain HTTP first and then HTTPS; an address
on the internet over HTTPS only, so a token is never sent unprotected unless
you type `http://` yourself.

## What the tab shows

```
Refresh                       340 recipes · 2 min ago        
Search                                                      ›
Category                      All                           ›
Order                         A to Z                        ›
Apple pie                     1 hour 20 minutes             ›
Banana bread                  1 hour                        ›
…
More recipes                  50 of 340                     ›
```

- **Search**: words to look for, with Mealie's own search (names,
  descriptions, ingredients). **All recipes** in the search box shows
  everything again.
- **Category**: one of your Mealie categories, or All.
- **Order**: A to Z, or the newest first.
- The recipes, 50 at a time, each with its total time; **More recipes** at
  the end fetches the next 50.

## The recipe box (Bookshelf view)

In the **Bookshelf** view (the one GZreader starts with; the quick panel's
**View** changes it), the tab is a recipe box on the kitchen counter instead of
a list:

- **The dividers' tabs** along the top are your Mealie categories, **All**
  first. Tap one to see its recipes; the chosen one stands taller, in black.
  When there are more categories than fit, the last tab is **More…**, which
  opens the full list.
- **The cards** filed in the box are the recipes: each shows its top edge with
  the name in handwriting and the total time. A page holds as many cards as
  the box is deep; turn pages as anywhere else.
- **On the box's front:** the brass label holder is **Search** (it shows the
  words you searched for), with two tags under it: the order (A to Z /
  Newest first) and **More cards** while Mealie has more.
- **Refresh** is the sign above the box.

On a keyboard Kindle everything that does something has a letter, and the
5-way moves over them. On a colour Kindle the box is wood, the cards cream
and the dividers' tabs coloured; it's drawn in greys everywhere else. The
other views keep the list.

## Reading a recipe

A recipe opens as a page of text: its description, how much it makes and how
long it takes, the **ingredients** (under their sections, if the recipe has
them), the **steps**, numbered, and the **notes**. Turn its pages with the
page keys or a swipe; Back closes it.

### The recipe card (Bookshelf view)

In the Bookshelf view a recipe is a ruled index card out of the recipe box:
its name in handwriting under a paper clip, what it makes and the times, and
its category on a divider's tab behind it. On the card's lines are the
ingredients, the steps and the notes.

- **Crossing off:** each ingredient has a circle. Tap the ingredient to cross
  it off, and again to bring it back; on a Kindle with a 5-way, move to it
  with Up and Down and press. What's crossed off is remembered until GZreader
  is restarted.
- **More than one card:** a long recipe continues on the next card. **Turn the
  card** (or tap the right of the card, swipe left, or use the page keys) and
  **Back** (the left of the card, swipe right) to go back. A heading is never
  left alone at the foot of a card.
- **Recipe box**, the Back key or a swipe down puts the card away.

On a colour Kindle the card is cream with blue lines and a red rule under the
name.

## Without Wi‑Fi in the kitchen

The list as last fetched is kept on the Kindle and shown at once when the tab
opens. Each recipe you open is kept too: it opens at once the next time, also
with Wi‑Fi off or Mealie out of reach, and is fetched again quietly for the
time after when Wi‑Fi is available. Recipes you've never opened need Mealie.

**Disconnect** (Settings → Accounts and services → Recipes) removes the
address, the token and the kept recipes from the Kindle.

## Not there yet

Pictures, scaling a recipe's amounts, meal plans, shopping lists and editing
recipes: the tab is for finding and reading.
