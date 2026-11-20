"""Turning IPA transcription strings into sequences of an accent's phonemes.

Every source writes IPA slightly differently (ɛ or e for DRESS, ɐ for STRUT in
one and for word-final schwa in another, syllabic consonants or not), so each
source supplies its own symbol table mapping its spellings onto the accent's
canonical phonemes. Anything not in the table is an error rather than being
skipped, so that new notation in a source gets noticed (and counted) instead
of silently producing a wrong phoneme count.
"""

import collections.abc
import itertools
import re
import unicodedata

# Marks that carry no segmental information for our purposes. Stress and
# syllable boundaries are dropped; the tie bar is dropped so that t͡ʃ and tʃ
# look the same to the symbol table; the non-syllabic mark is redundant in a
# phonemic transcription of diphthongs.
IGNORED = frozenset("ˈˌ.‿͡ ̯")

# Superscript and parenthesised linking/intrusive r, as in Wiktionary's
# /ˈfɑːðə(ɹ)/: never part of the citation form in a non-rhotic accent.
LINKING_R = re.compile(r"\(ɹ\)|\(r\)|⁽ʳ⁾|ʳ")

OPTIONAL = re.compile(r"\(([^()]*)\)")

Symbols = collections.abc.Mapping[str, tuple[str, ...]]


class UnknownSymbol(Exception):
    def __init__(self, *, symbol: str, transcription: str):
        super().__init__(f"{symbol!r} in {transcription!r}")
        self.symbol = symbol
        self.transcription = transcription


def variants(transcription: str) -> list[str]:
    """Split one transcription field into the plain IPA strings it allows.

    Handles /slashes/ or [brackets], comma- or tilde-separated alternatives,
    and optional segments in parentheses, which are expanded both ways.
    """
    text = unicodedata.normalize("NFC", transcription)
    text = LINKING_R.sub("", text)
    results = []
    for alternative in re.split(r"[,~]", text):
        alternative = alternative.strip().strip("/[]").strip()
        if not alternative:
            continue
        pieces = OPTIONAL.split(alternative)
        # OPTIONAL.split alternates fixed text with optional groups.
        fixed = pieces[0::2]
        optional = pieces[1::2]
        for choices in itertools.product((False, True), repeat=len(optional)):
            out = fixed[0]
            for chosen, group, after in zip(choices, optional, fixed[1:]):
                out += (group if chosen else "") + after
            results.append(out)
    return results


def tokenize(ipa: str, *, symbols: Symbols) -> tuple[str, ...]:
    """Greedy longest-match tokenisation of a plain IPA string."""
    text = unicodedata.normalize("NFC", ipa)
    text = "".join(c for c in text if c not in IGNORED)
    longest = max(map(len, symbols))
    phonemes: list[str] = []
    i = 0
    while i < len(text):
        for size in range(min(longest, len(text) - i), 0, -1):
            match = symbols.get(text[i : i + size])
            if match is not None:
                phonemes.extend(match)
                i += size
                break
        else:
            raise UnknownSymbol(symbol=text[i], transcription=ipa)
    return tuple(phonemes)


def tokenize_segmented(
    ipa: str, *, separator: str, symbols: Symbols
) -> tuple[str, ...]:
    """Tokenise a transcription whose source already separates its phonemes.

    Each segment is tokenised on its own, so that e.g. t followed by ʃ stays two
    phonemes even though tʃ is one. Segments can still contain several
    phonemes, for sources whose segmentation differs from ours, but they can't
    run into each other.
    """
    return tuple(
        phoneme
        for segment in re.split(separator, ipa)
        if segment.strip("ˈˌ")
        for phoneme in tokenize(segment, symbols=symbols)
    )
