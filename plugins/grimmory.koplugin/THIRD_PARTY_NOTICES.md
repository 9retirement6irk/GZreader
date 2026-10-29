# Third-party code in the GZreader plugin

## Grimmory-KOReader-Client

`grimmory_cfi.lua`, `grimmory_annosync.lua` and `grimmory_slaxml.lua` come from
[Grimmory-KOReader-Client](https://github.com/ManorianOTP/Grimmory-KOReader-Client)
(`grimmory_sync.koplugin/cfi.lua`, `annotations.lua` and `slaxml.lua`, commit
`560af98`). GZreader's changes, marked "GZreader" in the code: a cache of
parsed chapters, and archive paths with `%20` and `../` resolved.

```
MIT License

Copyright (c) 2026 ManorianOTP

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

## SLAXML

`grimmory_slaxml.lua` is SLAXML v0.8 (with the `dom()` builder from
`slaxdom.lua`) by Gavin Kistner, <https://github.com/Phrogz/SLAXML>, commit
`8a3e0c90325aa6d84ad23a7c13bf77247cb7f94e`. MIT License:
"v0.8 Copyright © 2013-2018 Gavin Kistner; MIT Licensed". The MIT terms are the
same as above.
