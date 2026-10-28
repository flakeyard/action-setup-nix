#!/usr/bin/env python3
"""Usage: nar-hash.py PATH...

Prints, for each PATH, the SHA-256 of its NAR serialization in the form Nix
writes it in narinfo files and .reginfo: sha256:<nix32>, then a space and the
NAR size. Independent of Nix, so that a Nix release can be checked without
trusting the Nix it contains.
"""

import hashlib
import os
import stat
import struct
import sys

NIX32 = "0123456789abcdfghijklmnpqrsvwxyz"


class Nar:
    def __init__(self):
        self.hash = hashlib.sha256()
        self.size = 0

    def write(self, data):
        self.hash.update(data)
        self.size += len(data)

    def string(self, data):
        self.write(struct.pack("<Q", len(data)))
        self.write(data)
        self.write(b"\0" * (-len(data) % 8))

    def node(self, path):
        info = os.lstat(path)
        self.string(b"(")
        self.string(b"type")
        if stat.S_ISLNK(info.st_mode):
            self.string(b"symlink")
            self.string(b"target")
            self.string(os.fsencode(os.readlink(path)))
        elif stat.S_ISREG(info.st_mode):
            self.string(b"regular")
            if info.st_mode & stat.S_IXUSR:
                self.string(b"executable")
                self.string(b"")
            self.string(b"contents")
            self.write(struct.pack("<Q", info.st_size))
            with open(path, "rb") as file:
                for chunk in iter(lambda: file.read(1 << 20), b""):
                    self.write(chunk)
            self.write(b"\0" * (-info.st_size % 8))
        elif stat.S_ISDIR(info.st_mode):
            self.string(b"directory")
            for name in sorted(os.listdir(os.fsencode(path))):
                self.string(b"entry")
                self.string(b"(")
                self.string(b"name")
                self.string(name)
                self.string(b"node")
                self.node(os.path.join(os.fsencode(path), name))
                self.string(b")")
        else:
            sys.exit(f"error: unsupported file type: {os.fsdecode(path)}")
        self.string(b")")


def nix32(digest):
    length = (len(digest) * 8 - 1) // 5 + 1
    chars = []
    for n in range(length - 1, -1, -1):
        bit = n * 5
        i, j = divmod(bit, 8)
        c = digest[i] >> j
        if i + 1 < len(digest):
            c |= digest[i + 1] << (8 - j)
        chars.append(NIX32[c & 0x1F])
    return "".join(chars)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        nar = Nar()
        nar.string(b"nix-archive-1")
        nar.node(path)
        print(f"sha256:{nix32(nar.hash.digest())} {nar.size}")


if __name__ == "__main__":
    main()
