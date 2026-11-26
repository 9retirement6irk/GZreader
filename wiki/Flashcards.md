Question-and-answer cards made from what you read by your AI service, kept as
notes in [Memos](Notes), and a quiz on the Kindle.

## Making cards

You need an AI key ([Setup page and connections → AI](Setup-Page-and-Connections#ai)).

- **From a chapter**: in a book, the quick panel's **Flashcards** → **Make
  cards from this chapter**. It asks first, saying how many words of the
  chapter go to your AI service (a long chapter: its first 12,000 characters or
  so). Ten cards are made.
- **From selected text**: select some text, then **Flashcards (AI)** in the
  selection menu (under **More** in the row of icons). Five cards are made.

The cards come back to check, with **Save** and **Cancel**. Sent: the text
(the chapter or the selection), and the book's title and author. An AI wrote
the cards and they can be wrong.

**Save** keeps them on the Kindle, and when Memos is connected also as a
private note in Memos, tagged `#flashcards`:

```
#flashcards
**Flashcards: Moby-Dick** · Loomings

Q: Who tells the story?
A: Ishmael.
```

You can read and edit the deck in Memos' web app. To use the cards in Anki,
copy the note's lines into a text file and import it there with `Q:` and `A:`
as the field names, or ask for a separate export.

Not yet: cards from a whole book, or answers to a test's questions from a
book.

## The quiz

The quick panel's **Flashcards** in a book → **Quiz me on this book** or **Quiz
me on all my cards** (each says how many are due). One card at a time, in
large type:

1. Read the question, then tap **Show answer**.
2. Tap **Again** if you missed it, **Got it** if you knew it.

A card you get moves up a box and is shown again after 1, then 3, 7 and 14
days. A missed one goes back to the first box and comes round again before the
quiz ends. At the end it says how many you got right the first time. **Stop**
ends the quiz early; what you answered is kept.

The quiz works with Wi‑Fi off: the decks the Kindle made are kept on it, with
where each card is (`gzreader_flashcards.lua` in GZreader's settings). The
**Flashcards** tile shows when an AI key is set up or there are cards to quiz.
