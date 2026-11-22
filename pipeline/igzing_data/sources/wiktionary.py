"""English Wiktionary, via kaikki.org's wiktextract dumps. CC BY-SA / GFDL.

Wiktionary gives pronunciations for many accents, with tagging that's helpful
but inconsistent. For each accent we produce two layers: transcriptions
explicitly tagged for the accent, and untagged ones from words that have no
tagged transcription. The latter are often accent-neutral, but sometimes just
some editor's own accent, so the build checks them more sceptically.

We also extract some word-level facts used to choose answers: which words
are dictionary headwords in their own right (rather than only inflections,
abbreviations or misspellings), and which have senses tagged offensive.
"""

import collections
import dataclasses
import gzip
import json
import re
import sys

from igzing_data import download, sourcefile

URL = "https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz"

WORD = re.compile(r"[a-z]+")
PHONEMIC = re.compile(r"/[^/]+/")


@dataclasses.dataclass(frozen=True)
class AccentTags:
    # Name of the accent's layers in data/sources.
    name: str
    # A transcription with any of these tags is for this accent, whatever
    # other accents it's also tagged with...
    sufficient: frozenset[str]
    # ...and one with any of these is too...
    tags: frozenset[str]
    # ...unless it also has a tag outside these, e.g. a regional one.
    compatible: frozenset[str]
    # Untagged transcriptions with notes are usually one of a list of
    # variants. These notes mark a variant as belonging to this accent.
    notes: frozenset[str]
    # Any transcription with one of these tags is excluded.
    excluded: frozenset[str] = frozenset()


EN_GB = AccentTags(
    name="wiktionary-en-GB",
    # RP alongside regional tags means the regions share it, as in "job",
    # tagged Canada, Northern-England, Received-Pronunciation, Wales. UK
    # alongside one means a variant within the UK, as in UK, Scotland.
    #
    # "British Southern Standard" transcriptions use Geoff Lindsey's notation
    # (/ɪj/, /ʉw/, /a/ for TRAP, ...), which is a different phonemic analysis
    # that we'd need a separate symbol table for. They're rejected as
    # incompatible with UK, unless they're also tagged RP, which means the
    # transcription is the same in both.
    sufficient=frozenset({"Received-Pronunciation"}),
    tags=frozenset({"UK"}),
    compatible=frozenset(
        {"General-American", "US", "Canada", "Australia", "New-Zealand"}
    ),
    notes=frozenset({"trap–bath split", "non-rhotic"}),
    excluded=frozenset(
        {
            "archaic",
            "obsolete",
            "dated",
            "rare",
            "uncommon",
            "nonstandard",
            "dialectal",
            "unstressed",
        }
    ),
)

ACCENTS = (EN_GB,)

# Parts of speech that don't make a word a headword in its own right.
NON_HEADWORD_POS = frozenset(
    {
        "name",
        "abbrev",
        "symbol",
        "character",
        "prefix",
        "suffix",
        "infix",
        "interfix",
        "affix",
        "circumfix",
        "punct",
        "phrase",
        "prep_phrase",
        "proverb",
        "contraction",
    }
)
NON_HEADWORD_TAGS = frozenset(
    {
        "abbreviation",
        "acronym",
        "initialism",
        "misspelling",
        "obsolete",
        "archaic",
        "nonstandard",
        "pronunciation-spelling",
        "alt-of",
        "form-of",
    }
)
OFFENSIVE_TAGS = frozenset(
    {"vulgar", "offensive", "derogatory", "slur", "ethnic", "pejorative"}
)


def _layer(sound: dict, accent: AccentTags) -> str | None:
    """Which of the accent's layers a transcription belongs in, if any."""
    tags = set(sound.get("tags", []))
    if tags & accent.excluded:
        return None
    if tags & accent.sufficient:
        return "tagged"
    if tags & accent.tags:
        return "tagged" if tags <= accent.tags | accent.compatible else None
    if tags or sound.get("raw_tags"):
        return None
    if "note" in sound:
        return "tagged" if sound["note"] in accent.notes else None
    return "untagged"


def fetch(*, refresh: bool) -> None:
    path = download.cached(URL, refresh=refresh)
    # spelling -> exact-case spelling -> accent -> layer -> transcriptions
    found = collections.defaultdict(
        lambda: collections.defaultdict(
            lambda: collections.defaultdict(lambda: collections.defaultdict(set))
        )
    )
    headwords = set()
    offensive = set()
    # Exact-case spellings with any transcription, for any accent
    has_ipa = set()
    with gzip.open(path, "rt", encoding="utf-8") as lines:
        for n, line in enumerate(lines):
            if n % 100_000 == 0:
                print(f"wiktionary: {n} entries", file=sys.stderr)
            entry = json.loads(line)
            if entry.get("lang_code") != "en":
                continue
            word = entry["word"]
            spelling = word.lower()
            if not WORD.fullmatch(spelling):
                continue
            senses = entry.get("senses", [])
            if any(OFFENSIVE_TAGS & set(s.get("tags", [])) for s in senses):
                offensive.add(spelling)
            if (
                word == spelling
                and entry["pos"] not in NON_HEADWORD_POS
                and any(
                    not (NON_HEADWORD_TAGS & set(s.get("tags", [])))
                    and not s.get("form_of")
                    and not s.get("alt_of")
                    for s in senses
                )
            ):
                headwords.add(spelling)
            for sound in entry.get("sounds", []):
                if "ipa" not in sound:
                    continue
                has_ipa.add(word)
                for accent in ACCENTS:
                    if layer := _layer(sound, accent):
                        found[spelling][word][accent.name][layer].update(
                            PHONEMIC.findall(sound["ipa"])
                        )

    for accent in ACCENTS:
        layers = {"tagged": [], "untagged": []}
        for spelling, by_case in found.items():
            # Use capitalised entries only when there's no transcription at all
            # for the lower-case one, so that e.g. "reading" doesn't get the
            # pronunciation of the town of Reading, nor "job" that of the
            # biblical Job when its own transcriptions are all for other
            # accents.
            if spelling in has_ipa:
                candidates = [by_case[spelling]] if spelling in by_case else []
            else:
                candidates = [v for _, v in sorted(by_case.items())]
            for by_accent in candidates:
                by_layer = by_accent.get(accent.name, {})
                # Untagged transcriptions only count for words with no tagged
                # ones, since when there are tagged ones the untagged ones are
                # usually for some other accent.
                layer = "tagged" if by_layer.get("tagged") else "untagged"
                if by_layer.get(layer):
                    layers[layer] += [(spelling, t) for t in by_layer[layer]]
                    break
        sourcefile.write(accent.name, layers["tagged"])
        sourcefile.write(f"{accent.name}-untagged", layers["untagged"])
    # Only words with some pronunciation could be answers, which keeps this
    # list to a manageable size.
    sourcefile.write(
        "wiktionary-headwords", [(w,) for w in headwords & {w.lower() for w in has_ipa}]
    )
    sourcefile.write("wiktionary-offensive", [(w,) for w in offensive])
