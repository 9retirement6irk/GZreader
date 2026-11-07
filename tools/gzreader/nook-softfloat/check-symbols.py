#!/usr/bin/env python3
"""Every library a program in the package needs is there: each ARM ELF file's
undefined (non-weak) dynamic symbols must be defined by another file in the
package or by the C library (the given system library folders).

A soft-float build can leave a library needing a symbol whose code compiled
to nothing (Tesseract's DotProductNEON: libk2pdfopt then didn't load, and
with it PDFs, the statistics plugin and GZreader's plugin).

  check-symbols.py <package dir> <system lib dir>... [--ignore <file name>...]
"""
import glob
import os
import subprocess
import sys

args = sys.argv[1:]
ignore = set()
if "--ignore" in args:
    i = args.index("--ignore")
    ignore = set(args[i + 1:])
    args = args[:i]
pkg, sysdirs = args[0], args[1:]


def elf_files(root):
    for dirpath, _dirs, names in os.walk(root):
        for n in names:
            p = os.path.join(dirpath, n)
            if os.path.isfile(p) and not os.path.islink(p):
                with open(p, "rb") as f:
                    if f.read(4) == b"\x7fELF":
                        yield p


def symbols(path, undefined):
    out = subprocess.run(["readelf", "--dyn-syms", "-W", path], capture_output=True, text=True).stdout
    found = set()
    for line in out.splitlines():
        p = line.split()
        if len(p) < 8 or not p[0].endswith(":"):
            continue
        name = p[7].split("@")[0]
        if not name:
            continue
        if undefined:
            if p[6] == "UND" and p[4] != "WEAK":
                found.add(name)
        elif p[6] != "UND" and p[4] != "LOCAL":
            found.add(name)
    return found


files = list(elf_files(pkg))
system = [p for d in sysdirs for p in glob.glob(os.path.join(d, "*.so*")) if os.path.isfile(p)]
defined = set()
for f in files + system:
    defined |= symbols(f, False)
bad = 0
for f in files:
    if os.path.basename(f) in ignore:
        continue
    missing = sorted(symbols(f, True) - defined)
    if missing:
        bad += 1
        print("missing in %s: %s" % (os.path.relpath(f, pkg), ", ".join(missing[:8])))
print("%d ARM files checked, %d need something nothing here provides" % (len(files), bad))
sys.exit(1 if bad or not files else 0)
