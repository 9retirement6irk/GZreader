# Handwriting to text: where this comes from

GZreader reads handwriting on the Kindle with the reader, model and word list
of **Ink Away** (https://github.com/EmirErtorer/ink-away.koplugin), used as
they are: `gzreader_hwr.lua`, `gzreader_hwrnet.lua` and `gzreader_hwrwords.lua`
(Ink Away's `ink/hwr.lua`, `ink/hwrnet.lua`, `ink/hwrwords.lua`), and this
folder's `hwr_en.bin` and `hwr_words_en.txt`.

## Ink Away's license

```
MIT License

Copyright (c) 2026 Emir Devlet Ertörer (@EmirErtorer)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Ink Away's notice for the model and the word list


`hwr_en.bin` is a small neural network trained by the author to read
handwritten characters (the training code is a separate project). It was
trained on:

- EMNIST (Cohen, Afshar, Tapson and van Schaik, 2017), derived from NIST
  Special Database 19, a work of the U.S. government.
- UJI Pen Characters, version 2 (Prat, Castro, Llorens, Marzal and Vilar,
  Universitat Jaume I, 2008), from the UCI Machine Learning Repository,
  licensed under Creative Commons Attribution 4.0
  (https://creativecommons.org/licenses/by/4.0/). `tools/gzreader/tests/hwr_vectors.lua`
  holds a few of its strokes.

`hwr_words_en.txt` is taken from SCOWL (Spell Checker Oriented Word
Lists, http://wordlist.aspell.net), levels 10 to 40, American and British
spellings, plain lower-case words only. Its notice:

> Copyright 2000-2018 by Kevin Atkinson
>
> Permission to use, copy, modify, distribute and sell these word lists, the
> associated scripts, the output created from the scripts, and its
> documentation for any purpose is hereby granted without fee, provided that
> the above copyright notice appears in all copies and that both that
> copyright notice and this permission notice appear in supporting
> documentation. Kevin Atkinson makes no representations about the
> suitability of this array for any purpose. It is provided "as is" without
> express or implied warranty.

SCOWL also includes material from the Moby Words II lists (public domain), the
12Dicts package by Alan Beale and other sources credited in SCOWL's own
Copyright file.

