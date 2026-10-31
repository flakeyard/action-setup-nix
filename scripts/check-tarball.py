#!/usr/bin/env -S python3 -ISB
"""Usage: check-tarball.py TARBALL
       check-tarball.py --nar-hash PATH...

Checks a Nix release tarball against cache.nixos.org: every store path in it
must be in the cache, signed by cache.nixos.org-1, with the NAR hash, size and
references of the store path's contents in the tarball, and the tarball must
contain no other store paths. The installer scripts next to the store are not
covered by any signature; update-nix.sh shows their changes.

With --nar-hash, prints for each PATH the NAR hash in the form of narinfo files
and .reginfo, sha256:<nix32>, then a space and the NAR size.

Needs curl, openssl, tar and xz; not Nix, so that a Nix release can be checked
without trusting the Nix it contains. Python 3.12 or later, standard library
only.
"""

import base64
import binascii
import dataclasses
import hashlib
import os
import re
import stat
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

CACHE_URL = "https://cache.nixos.org"
CACHE_KEY = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="

STORE_DIR = "/nix/store"
# <hash>-<name> of a store path; the hash in Nix's base-32 alphabet.
STORE_NAME = r"[0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]+"
STORE_PATH_RE = re.compile(re.escape(STORE_DIR) + "/(" + STORE_NAME + ")")
NAR_HASH_RE = re.compile(r"sha256:[0-9a-df-np-sv-z]{52}")
NUMBER_RE = re.compile(r"[0-9]{1,12}")

# The DER SubjectPublicKeyInfo of an Ed25519 key, before the 32 key bytes.
ED25519_DER_PREFIX = bytes.fromhex("302a300506032b6570032100")

CURL = ["curl", "--proto", "=https", "--silent", "--show-error", "--retry", "3"]
HTTP_OK = "200"


class CheckError(Exception):
    """A check failed; the message says which."""


# --- NAR serialization and nix32 ----------------------------------------------

NIX32_ALPHABET = "0123456789abcdfghijklmnpqrsvwxyz"
BITS_PER_BYTE = 8
BITS_PER_CHAR = 5
CHAR_MASK = (1 << BITS_PER_CHAR) - 1
NAR_ALIGNMENT = 8
READ_CHUNK = 1 << 20


def nix32(digest: bytes) -> str:
    """digest in Nix's base 32: the last 5 bits first, without padding."""
    length = (len(digest) * BITS_PER_BYTE - 1) // BITS_PER_CHAR + 1
    chars = []
    for n in reversed(range(length)):
        byte, shift = divmod(n * BITS_PER_CHAR, BITS_PER_BYTE)
        value = digest[byte] >> shift
        if byte + 1 < len(digest):
            value |= digest[byte + 1] << (BITS_PER_BYTE - shift)
        chars.append(NIX32_ALPHABET[value & CHAR_MASK])
    return "".join(chars)


class NarHasher:
    """The SHA-256 and the size of the NAR serialization of a path."""

    def __init__(self) -> None:
        self.hash = hashlib.sha256()
        self.size = 0

    def write(self, data: bytes) -> None:
        self.hash.update(data)
        self.size += len(data)

    def pad(self, length: int) -> None:
        self.write(b"\0" * (-length % NAR_ALIGNMENT))

    def string(self, data: bytes) -> None:
        self.write(struct.pack("<Q", len(data)))
        self.write(data)
        self.pad(len(data))

    def strings(self, *items: bytes) -> None:
        for item in items:
            self.string(item)

    def node(self, path: bytes) -> None:
        mode = os.lstat(path).st_mode
        self.strings(b"(", b"type")
        if stat.S_ISLNK(mode):
            self.strings(b"symlink", b"target", os.readlink(path))
        elif stat.S_ISREG(mode):
            self.regular(path, executable=bool(mode & stat.S_IXUSR))
        elif stat.S_ISDIR(mode):
            self.directory(path)
        else:
            raise CheckError(f"unsupported file type: {os.fsdecode(path)}")
        self.string(b")")

    def regular(self, path: bytes, executable: bool) -> None:
        self.string(b"regular")
        if executable:
            self.strings(b"executable", b"")
        self.string(b"contents")
        with open(path, "rb") as file:
            size = os.fstat(file.fileno()).st_size
            self.write(struct.pack("<Q", size))
            for chunk in iter(lambda: file.read(READ_CHUNK), b""):
                self.write(chunk)
        self.pad(size)

    def directory(self, path: bytes) -> None:
        self.string(b"directory")
        for name in sorted(os.listdir(path)):
            self.strings(b"entry", b"(", b"name", name, b"node")
            self.node(os.path.join(path, name))
            self.string(b")")


def nar_hash(path: Path) -> tuple[str, int]:
    """The NAR hash, as sha256:<nix32>, and the NAR size of path."""
    nar = NarHasher()
    nar.string(b"nix-archive-1")
    nar.node(os.fsencode(path))
    return f"sha256:{nix32(nar.hash.digest())}", nar.size


# --- .reginfo -----------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class RegInfoEntry:
    """A store path as .reginfo lists it. Sizes stay strings, as in narinfo."""

    path: str
    name: str
    nar_hash: str
    nar_size: str
    references: tuple[str, ...]


class Lines:
    """The lines of a file, read one at a time."""

    def __init__(self, text: str) -> None:
        self.lines = text.split("\n")
        if self.lines[-1] == "":
            self.lines.pop()
        self.next = 0

    def read(self) -> str | None:
        if self.next == len(self.lines):
            return None
        self.next += 1
        return self.lines[self.next - 1]


def store_name(path: str) -> str | None:
    match = STORE_PATH_RE.fullmatch(path)
    return match.group(1) if match else None


def read_entry(path: str, lines: Lines) -> RegInfoEntry:
    """The entry of path: NAR hash, NAR size, deriver, number of references
    and the references. Every field is checked before it is used: the tarball
    is not trusted yet."""
    fields = [lines.read() for _ in range(4)]
    if None in fields:
        raise CheckError(f"truncated .reginfo after {path}")
    hash_, size, _deriver, count = fields
    name = store_name(path)
    if name is None:
        raise CheckError(f"invalid store path in .reginfo: {path}")
    if not NAR_HASH_RE.fullmatch(hash_):
        raise CheckError(f"invalid NAR hash for {path}")
    if not (NUMBER_RE.fullmatch(size) and NUMBER_RE.fullmatch(count)):
        raise CheckError(f"invalid size or reference count for {path}")
    references = tuple(read_reference(path, lines) for _ in range(int(count)))
    return RegInfoEntry(path, name, hash_, size, references)


def read_reference(path: str, lines: Lines) -> str:
    reference = lines.read()
    if reference is None:
        raise CheckError(f"truncated references of {path}")
    name = store_name(reference)
    if name is None:
        raise CheckError(f"invalid reference of {path}: {reference}")
    return name


def read_reginfo(file: Path) -> list[RegInfoEntry]:
    lines = Lines(file.read_text(errors="surrogateescape"))
    entries: list[RegInfoEntry] = []
    names: set[str] = set()
    while (path := lines.read()) is not None:
        if not path:
            continue
        entry = read_entry(path, lines)
        if entry.name in names:
            raise CheckError(f"{path} is listed twice")
        names.add(entry.name)
        entries.append(entry)
    if not entries:
        raise CheckError("no store paths in .reginfo")
    return entries


# --- The tarball --------------------------------------------------------------


def unpack(tarball: Path, work: Path) -> Path:
    """Unpacks tarball with tar, not tarfile, whose filters reject the
    release, and returns its one top-level directory."""
    target = work / "tar"
    target.mkdir()
    run_tool(
        ["tar", "--extract", "--xz", "--file", str(tarball), "--directory", str(target)]
    )
    dirs = [entry for entry in target.iterdir() if is_visible_dir(entry)]
    if len(dirs) != 1:
        raise CheckError(f"expected one top-level directory in {tarball}")
    top = dirs[0]
    if not ((top / ".reginfo").is_file() and (top / "store").is_dir()):
        raise CheckError(f"no .reginfo or store in {tarball}")
    return top


def is_visible_dir(path: Path) -> bool:
    return path.is_dir() and not path.name.startswith(".")


def check_contents(store: Path, entries: list[RegInfoEntry]) -> None:
    """The store holds exactly the entries, with their NAR hashes and sizes."""
    listed = {entry.name for entry in entries}
    for entry in os.listdir(store):
        if entry not in listed:
            raise CheckError(f"store/{entry} is not listed in .reginfo")
    for entry in entries:
        contents = store / entry.name
        if not (contents.exists() or contents.is_symlink()):
            raise CheckError(f"{entry.path} is not in the tarball")
        actual_hash, actual_size = nar_hash(contents)
        if (actual_hash, str(actual_size)) != (entry.nar_hash, entry.nar_size):
            raise CheckError(f"the contents of {entry.path} do not match .reginfo")


# --- The cache ----------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class NarInfo:
    """A narinfo file of the cache: each field with all its values."""

    fields: dict[str, list[str]]

    @classmethod
    def parse(cls, text: str) -> "NarInfo":
        fields: dict[str, list[str]] = {}
        for line in text.split("\n"):
            key, sep, value = line.partition(": ")
            if sep:
                fields.setdefault(key, []).append(value)
        return cls(fields)

    def value(self, key: str) -> str | None:
        """The value of a field that must appear once."""
        values = self.fields.get(key, [])
        return values[0] if len(values) == 1 else None

    def references(self) -> list[str]:
        return " ".join(self.fields.get("References", [])).split()

    def signatures(self) -> list[str]:
        return self.fields.get("Sig", [])


def store_hash(entry: RegInfoEntry) -> str:
    return entry.name.split("-", 1)[0]


def fetch_narinfos(entries: list[RegInfoEntry], work: Path) -> list[NarInfo]:
    """The narinfos of all entries, in one curl that reuses its connection."""
    files = [work / f"{store_hash(entry)}.narinfo" for entry in entries]
    args = [*CURL, "--write-out", r"%{http_code}\n"]
    for entry, file in zip(entries, files):
        args += [f"{CACHE_URL}/{store_hash(entry)}.narinfo", "--output", str(file)]
    result = subprocess.run(args, stdout=subprocess.PIPE, text=True, check=False)
    codes = result.stdout.split()
    if result.returncode != 0 or len(codes) != len(entries):
        raise CheckError(f"cannot fetch the narinfos from {CACHE_URL}")
    for entry, code in zip(entries, codes):
        if code != HTTP_OK:
            raise CheckError(f"{CACHE_URL} returned HTTP {code} for {entry.path}")
    return [NarInfo.parse(file.read_text(errors="surrogateescape")) for file in files]


def matches(entry: RegInfoEntry, info: NarInfo) -> bool:
    return (
        info.value("StorePath") == entry.path
        and info.value("NarHash") == entry.nar_hash
        and info.value("NarSize") == entry.nar_size
        and sorted(info.references()) == sorted(entry.references)
    )


def fingerprint(entry: RegInfoEntry, info: NarInfo) -> bytes:
    """What the cache signs, with the references in the order it lists them."""
    references = ",".join(f"{STORE_DIR}/{ref}" for ref in info.references())
    return f"1;{entry.path};{entry.nar_hash};{entry.nar_size};{references}".encode()


class Verifier:
    """Checks Ed25519 signatures of one key with openssl."""

    def __init__(self, key: str, work: Path) -> None:
        self.name, _, public = key.partition(":")
        self.key_file = work / "key.der"
        self.data_file = work / "data"
        self.sig_file = work / "sig"
        self.key_file.write_bytes(ED25519_DER_PREFIX + base64.b64decode(public))

    def signed(self, data: bytes, signatures: list[str]) -> bool:
        """Whether one of signatures, name:<base64>, is a valid one of data."""
        self.data_file.write_bytes(data)
        return any(self.valid(signature) for signature in signatures)

    def valid(self, signature: str) -> bool:
        name, _, value = signature.partition(":")
        if name != self.name:
            return False
        try:
            self.sig_file.write_bytes(base64.b64decode(value, validate=True))
        except binascii.Error:
            return False
        verify = ["openssl", "pkeyutl", "-verify", "-pubin", "-keyform", "DER"]
        verify += ["-inkey", str(self.key_file), "-rawin", "-in", str(self.data_file)]
        verify += ["-sigfile", str(self.sig_file)]
        result = subprocess.run(verify, capture_output=True, check=False)
        return result.returncode == 0


def check_cache(entries: list[RegInfoEntry], work: Path) -> None:
    verifier = Verifier(CACHE_KEY, work)
    for entry, info in zip(entries, fetch_narinfos(entries, work)):
        if not matches(entry, info):
            raise CheckError(f"{entry.path} in the tarball differs from {CACHE_URL}")
        if not verifier.signed(fingerprint(entry, info), info.signatures()):
            raise CheckError(f"no valid signature of {verifier.name} for {entry.path}")


# --- Main ---------------------------------------------------------------------


def run_tool(args: list[str]) -> None:
    if subprocess.run(args, check=False).returncode != 0:
        raise CheckError(f"{args[0]} failed")


def check_tarball(tarball: Path) -> int:
    """Checks tarball and returns the number of its store paths."""
    with tempfile.TemporaryDirectory() as temp:
        work = Path(temp)
        top = unpack(tarball, work)
        entries = read_reginfo(top / ".reginfo")
        check_contents(top / "store", entries)
        check_cache(entries, work)
        return len(entries)


def print_nar_hashes(paths: list[str]) -> None:
    for path in paths:
        hash_, size = nar_hash(Path(path))
        print(f"{hash_} {size}")


def main(args: list[str]) -> None:
    os.environ["LC_ALL"] = "C"
    try:
        if len(args) >= 2 and args[0] == "--nar-hash":
            print_nar_hashes(args[1:])
        elif len(args) == 1 and not args[0].startswith("-"):
            count = check_tarball(Path(args[0]))
            print(f"{count} store paths match {CACHE_URL} and its signatures.")
        else:
            sys.exit(__doc__)
    except CheckError as error:
        sys.exit(f"error: {error}")


if __name__ == "__main__":
    main(sys.argv[1:])
