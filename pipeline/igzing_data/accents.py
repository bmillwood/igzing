"""Accent definitions: the phoneme inventory, and how the game should present it.

The pronunciation sources for each accent live alongside the build code, since
they need code to read them; see build.py.
"""

import dataclasses


@dataclasses.dataclass(frozen=True)
class Phoneme:
    # Canonical identifier, used in the data files. An IPA transcription, so
    # that the data files are readable.
    id: str
    # How the phoneme is shown on keys and tiles; often but not always the id.
    label: str
    # A word containing the phoneme, as (before, highlighted, after), for the
    # keyboard's pronunciation key. For vowels, the Wells lexical set keyword
    # where there's one that suits.
    example: tuple[str, str, str]
    vowel: bool


@dataclasses.dataclass(frozen=True)
class Accent:
    # BCP 47 tag, also used as the accent's file name.
    tag: str
    name: str
    phonemes: tuple[Phoneme, ...]
    # Keyboard rows, as phoneme ids.
    keyboard: tuple[tuple[str, ...], ...]

    def ids(self) -> frozenset[str]:
        return frozenset(p.id for p in self.phonemes)

    def vowels(self) -> frozenset[str]:
        return frozenset(p.id for p in self.phonemes if p.vowel)


def _ex(word: str) -> tuple[str, str, str]:
    """Parse "tr[a]p" into ("tr", "a", "p")."""
    before, rest = word.split("[")
    highlighted, after = rest.split("]")
    return (before, highlighted, after)


def _phonemes(
    *, vowels: list[tuple[str, str, str]], consonants: list[tuple[str, str, str]]
) -> tuple[Phoneme, ...]:
    return tuple(
        Phoneme(id=i, label=label, example=_ex(ex), vowel=vowel)
        for rows, vowel in ((vowels, True), (consonants, False))
        for i, label, ex in rows
    )


EN_GB = Accent(
    tag="en-GB",
    name="British English (Standard Southern British)",
    phonemes=_phonemes(
        vowels=[
            # Short vowels
            ("ɪ", "ɪ", "k[i]t"),
            ("e", "e", "dr[e]ss"),
            ("æ", "æ", "tr[a]p"),
            ("ʌ", "ʌ", "str[u]t"),
            ("ɒ", "ɒ", "l[o]t"),
            ("ʊ", "ʊ", "f[oo]t"),
            ("ə", "ə", "comm[a]"),
            # Long vowels
            ("iː", "iː", "fl[ee]ce"),
            ("ɑː", "ɑː", "b[a]th"),
            ("ɔː", "ɔː", "th[ough]t"),
            ("uː", "uː", "g[oo]se"),
            ("ɜː", "ɜː", "n[ur]se"),
            # Diphthongs
            ("eɪ", "eɪ", "f[a]ce"),
            ("aɪ", "aɪ", "pr[i]ce"),
            ("ɔɪ", "ɔɪ", "ch[oi]ce"),
            ("əʊ", "əʊ", "g[oa]t"),
            ("aʊ", "aʊ", "m[ou]th"),
            ("ɪə", "ɪə", "n[ear]"),
            ("eə", "eə", "squ[are]"),
            ("ʊə", "ʊə", "c[ure]"),
        ],
        consonants=[
            ("p", "p", "[p]ie"),
            ("b", "b", "[b]uy"),
            ("t", "t", "[t]ie"),
            ("d", "d", "[d]ie"),
            ("k", "k", "[k]ite"),
            ("g", "g", "[g]uy"),
            ("tʃ", "tʃ", "[ch]in"),
            ("dʒ", "dʒ", "[j]am"),
            ("f", "f", "[f]ight"),
            ("v", "v", "[v]ie"),
            ("θ", "θ", "[th]igh"),
            ("ð", "ð", "[th]y"),
            ("s", "s", "[s]igh"),
            ("z", "z", "[z]oo"),
            ("ʃ", "ʃ", "[sh]y"),
            ("ʒ", "ʒ", "mea[s]ure"),
            ("h", "h", "[h]igh"),
            ("m", "m", "[m]y"),
            ("n", "n", "[n]igh"),
            ("ŋ", "ŋ", "si[ng]"),
            ("l", "l", "[l]ie"),
            ("r", "r", "[r]ye"),
            ("w", "w", "[w]ise"),
            ("j", "j", "[y]es"),
        ],
    ),
    keyboard=(
        ("ɪ", "e", "æ", "ʌ", "ɒ", "ʊ", "ə"),
        ("iː", "ɑː", "ɔː", "uː", "ɜː", "ɪə", "eə", "ʊə"),
        ("eɪ", "aɪ", "ɔɪ", "əʊ", "aʊ"),
        ("p", "b", "t", "d", "k", "g", "tʃ", "dʒ"),
        ("f", "v", "θ", "ð", "s", "z", "ʃ", "ʒ", "h"),
        ("m", "n", "ŋ", "l", "r", "w", "j"),
    ),
)

ACCENTS = {accent.tag: accent for accent in (EN_GB,)}
