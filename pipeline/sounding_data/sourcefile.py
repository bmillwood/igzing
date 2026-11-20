"""The committed, normalised output of the fetch stage.

Each source file is a sorted TSV of (word, transcription) pairs, with a word
repeated if it has several transcriptions. Transcriptions are left in the
source's own notation, so that changing how we interpret the notation doesn't
need a refetch.
"""

import collections.abc
import pathlib

DIR = pathlib.Path("data/sources")


def write(name: str, rows: collections.abc.Iterable[tuple[str, ...]]) -> None:
    DIR.mkdir(parents=True, exist_ok=True)
    lines = sorted({"\t".join(row) for row in rows})
    (DIR / f"{name}.tsv").write_text(
        "".join(line + "\n" for line in lines), encoding="utf-8"
    )


def read(name: str) -> list[tuple[str, ...]]:
    text = (DIR / f"{name}.tsv").read_text(encoding="utf-8")
    return [tuple(line.split("\t")) for line in text.splitlines()]
