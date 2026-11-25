"""Britfone: a hand-checked SSBE dictionary of ~16k common words. MIT licence.

https://github.com/JoseLlarena/Britfone
"""

import re

from igzing_data import download, sourcefile

COMMIT = "1062be14adc96c358f2087ac5449d72130c7a6f4"
URL = f"https://raw.githubusercontent.com/JoseLlarena/Britfone/{COMMIT}/britfone.main.3.0.1.csv"
# Which says that redistributing it, as we do in data/sources and in the
# game's data, means keeping its copyright notice with it.
LICENCE_URL = (
    f"https://raw.githubusercontent.com/JoseLlarena/Britfone/{COMMIT}/LICENSE.txt"
)
LICENCE = sourcefile.DIR / "britfone-LICENSE.txt"

ENTRY = re.compile(r"([A-Z]+)(?:\(\d+\))?, (.*)")

# Britfone writes STRUT as ɐ and happY as i (see its README), and syllabic
# consonants as schwa plus consonant already.
SYMBOLS = {"ɐ": ("ʌ",), "ɛ": ("e",), "ɛə": ("eə",), "i": ("iː",), "ɹ": ("r",)}


def fetch(*, refresh: bool) -> None:
    path = download.cached(URL, refresh=refresh)
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        # Entries with apostrophes or underscores (multi-word) don't match.
        if match := ENTRY.fullmatch(line):
            word, ipa = match.groups()
            entries.append((word.lower(), ipa))
    sourcefile.write("britfone", entries)
    LICENCE.write_bytes(download.cached(LICENCE_URL, refresh=refresh).read_bytes())
