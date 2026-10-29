#!/usr/bin/env python3
"""Build a compact StarDict dictionary from Open English WordNet (WN-LMF XML).

Usage: build-wordnet-stardict.py english-wordnet-2025.xml.gz OUTDIR

Writes OUTDIR/oewn.{ifo,idx,dict,syn}; run `dictzip OUTDIR/oewn.dict` after
to get oewn.dict.dz (KOReader's sdcv reads both).

Open English WordNet is licensed CC BY 4.0
(https://github.com/globalwordnet/english-wordnet); the attribution is
written into the .ifo description.
"""
import gzip
import html
import struct
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict, defaultdict

POS_NAMES = {"n": "noun", "v": "verb", "a": "adjective", "s": "adjective",
             "r": "adverb", "c": "conjunction", "p": "adposition", "x": "other", "u": "other"}
POS_ORDER = ["noun", "verb", "adjective", "adverb", "conjunction", "adposition", "other"]
VOWELS = set("aeiou")


def stardict_key(word_bytes):
    # StarDict ordering: g_ascii_strcasecmp, then strcmp. bytes.lower() only
    # lowers ASCII, exactly like g_ascii_strcasecmp.
    return (word_bytes.lower(), word_bytes)


def regular_forms(lemma, pos):
    """Simple regular English inflections so e.g. "books", "walked" hit the headword.
    Irregular forms come from the WordNet <Form> elements."""
    if " " in lemma or not lemma.isalpha() or not lemma.islower() or len(lemma) < 3:
        return set()
    w = lemma
    out = set()
    if pos == "noun" or pos == "verb":
        if w.endswith(("s", "x", "z", "ch", "sh")):
            out.add(w + "es")
        elif w.endswith("y") and w[-2] not in VOWELS:
            out.add(w[:-1] + "ies")
        else:
            out.add(w + "s")
    if pos == "verb":
        if w.endswith("e"):
            out.update({w + "d", w[:-1] + "ing"})
        elif w.endswith("y") and w[-2] not in VOWELS:
            out.update({w[:-1] + "ied", w + "ing"})
        else:
            out.update({w + "ed", w + "ing"})
            # stop -> stopped/stopping (short CVC words)
            if len(w) <= 4 and w[-1] not in VOWELS | {"w", "x", "y"} and w[-2] in VOWELS and w[-3] not in VOWELS:
                out.update({w + w[-1] + "ed", w + w[-1] + "ing"})
    if pos == "adjective" and len(w) <= 6:
        if w.endswith("e"):
            out.update({w + "r", w + "st"})
        elif w.endswith("y") and w[-2] not in VOWELS:
            out.update({w[:-1] + "ier", w[:-1] + "iest"})
        else:
            out.update({w + "er", w + "est"})
    out.discard(lemma)
    return out


def main(src, outdir):
    opener = gzip.open if src.endswith(".gz") else open
    with opener(src, "rb") as f:
        root = ET.parse(f).getroot()
    lexicon = root.find("Lexicon")
    version = lexicon.get("version", "")

    synsets = {}
    for ss in lexicon.iter("Synset"):
        d = ss.find("Definition")
        synsets[ss.get("id")] = {
            "def": (d.text or "").strip() if d is not None else "",
            "examples": [(e.text or "").strip() for e in ss.findall("Example") if (e.text or "").strip()],
            "members": [],
        }

    # headword -> pos -> [synset ids]; also synset -> member lemmas
    entries = defaultdict(lambda: OrderedDict())
    forms = defaultdict(set)  # inflected/variant form -> headwords
    for le in lexicon.iter("LexicalEntry"):
        lemma_el = le.find("Lemma")
        lemma = lemma_el.get("writtenForm")
        pos = POS_NAMES.get(lemma_el.get("partOfSpeech"), "other")
        for s in le.findall("Sense"):
            sid = s.get("synset")
            if sid in synsets:
                entries[lemma].setdefault(pos, []).append(sid)
                if lemma not in synsets[sid]["members"]:
                    synsets[sid]["members"].append(lemma)
        for fm in le.findall("Form"):
            wf = fm.get("writtenForm")
            if wf and wf != lemma:
                forms[wf].add(lemma)
        for wf in regular_forms(lemma, pos):
            forms[wf].add(lemma)

    def render(lemma, by_pos):
        parts = []
        for pos in sorted(by_pos, key=lambda p: POS_ORDER.index(p) if p in POS_ORDER else 99):
            parts.append("<p><b><i>%s</i></b></p><ol>" % pos)
            for sid in by_pos[pos]:
                ss = synsets[sid]
                li = html.escape(ss["def"])
                for ex in ss["examples"][:2]:
                    li += ' <i>&ldquo;%s&rdquo;</i>' % html.escape(ex.strip('"'))
                syn = [m for m in ss["members"] if m != lemma][:6]
                if syn:
                    li += "<br/><small>Synonyms: %s</small>" % html.escape(", ".join(syn))
                parts.append("<li>%s</li>" % li)
            parts.append("</ol>")
        return "".join(parts)

    words = sorted(entries.keys(), key=lambda w: stardict_key(w.encode("utf-8")))
    index_of = {}
    dict_data = bytearray()
    idx = bytearray()
    for i, w in enumerate(words):
        body = render(w, entries[w]).encode("utf-8")
        wb = w.encode("utf-8")
        idx += wb + b"\0" + struct.pack(">II", len(dict_data), len(body))
        dict_data += body
        index_of[w] = i

    syn_items = []
    for form, heads in forms.items():
        if form in entries:
            continue  # it's a headword itself
        for h in heads:
            syn_items.append((form.encode("utf-8"), index_of[h]))
    syn_items.sort(key=lambda t: (stardict_key(t[0]), t[1]))
    syn = bytearray()
    for fb, i in syn_items:
        syn += fb + b"\0" + struct.pack(">I", i)

    base = outdir.rstrip("/") + "/oewn"
    open(base + ".dict", "wb").write(dict_data)
    open(base + ".idx", "wb").write(idx)
    open(base + ".syn", "wb").write(syn)
    ifo = "\n".join([
        "StarDict's dict ifo file",
        "version=3.0.0",
        "bookname=Open English WordNet %s" % version,
        "wordcount=%d" % len(words),
        "synwordcount=%d" % len(syn_items),
        "idxfilesize=%d" % len(idx),
        "sametypesequence=h",
        "author=Open English WordNet contributors",
        "website=https://github.com/globalwordnet/english-wordnet",
        "description=Open English WordNet %s (https://en-word.net), licensed CC BY 4.0. "
        "Converted to StarDict for the Grimmory KOReader build." % version,
        "",
    ])
    open(base + ".ifo", "w", encoding="utf-8").write(ifo)
    print("words=%d synonyms=%d dict=%d bytes" % (len(words), len(syn_items), len(dict_data)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
