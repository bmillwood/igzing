"""The CMU Pronouncing Dictionary: ~130k words in General American, in
ARPAbet with stress digits. BSD-style licence.

https://github.com/cmusphinx/cmudict
"""

import re

from igzing_data import download, sourcefile

COMMIT = "74790861f652b15e4ac49015a90074ad62a27690"
URL = f"https://raw.githubusercontent.com/cmusphinx/cmudict/{COMMIT}/cmudict.dict"
# Which says that redistributing it, as we do in data/sources and in the
# game's data, means keeping its copyright notice with it.
LICENCE_URL = f"https://raw.githubusercontent.com/cmusphinx/cmudict/{COMMIT}/LICENSE"
LICENCE = sourcefile.DIR / "cmudict-LICENSE.txt"

# "word ARPA BET" or "word(2) ARPA BET" for a variant, maybe with a comment.
ENTRY = re.compile(r"([a-z]+)(?:\(\d+\))? ([A-Z0-9 ]+?)(?: #.*)?")


def fetch(*, refresh: bool) -> None:
    path = download.cached(URL, refresh=refresh)
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        # Entries with apostrophes, dots, digits etc. don't match.
        if match := ENTRY.fullmatch(line):
            entries.append(match.groups())
    sourcefile.write("cmudict", entries)
    LICENCE.write_bytes(download.cached(LICENCE_URL, refresh=refresh).read_bytes())
