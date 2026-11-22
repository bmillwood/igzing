"""Build the game's per-accent data files from the fetched sources.

Each accent has a stack of pronunciation layers, best first. A word's
pronunciations come from the first layer that has any usable pronunciation
for it; lower layers only fill gaps. That way a big, noisy source like espeak
widens what counts as a valid guess without overruling a careful source on
words they both know.

Answers are chosen more strictly: see `_answers`.
"""

import collections
import collections.abc
import dataclasses
import json
import pathlib
import re
import sys

import wordfreq

from sounding_data import accents, ipa, sourcefile
from sounding_data.sources import britfone, espeak

Pronunciation = tuple[str, ...]

# Lengths, in phonemes, of the answers we provide. The game defaults to 5.
ANSWER_LENGTHS = (4, 5, 6)
# Minimum Zipf frequency (log10 of occurrences per billion words) for an
# answer: roughly, words you'd expect most adults to know.
ANSWER_ZIPF = 3.0
# Minimum Zipf frequency for a word we have no curated pronunciation for to be
# included at all, using espeak's guess at its pronunciation.
ESPEAK_ZIPF = 2.5


@dataclasses.dataclass(frozen=True)
class Layer:
    name: str
    # Whether the layer's pronunciations are trustworthy enough for answers.
    curated: bool
    symbols: ipa.Symbols
    # For sources that separate their phonemes, the separator.
    separator: str | None = None
    # Reject pronunciations that look rhotic, for accents that aren't.
    non_rhotic: bool = False
    # Reject transcriptions with several primary stresses. When espeak can't
    # pronounce something, it spells it out letter by letter, stressing each.
    one_primary_stress: bool = False
    # Produce the layer's raw (word, transcription) rows, given the words that
    # still lack a pronunciation. Defaults to reading data/sources/{name}.tsv.
    generate: collections.abc.Callable[[set[str]], list[tuple[str, str]]] | None = None


@dataclasses.dataclass(frozen=True)
class AccentBuild:
    accent: accents.Accent
    layers: tuple[Layer, ...]


def _rp_symbols(extra: ipa.Symbols) -> dict[str, tuple[str, ...]]:
    table = {p.id: (p.id,) for p in accents.EN_GB.phonemes}
    table |= {
        "ɛ": ("e",),
        "ɡ": ("g",),
        "ɹ": ("r",),
        "ʍ": ("w",),
        "ɫ": ("l",),
        # happY and thankYOU vowels: see _happy_tensing.
        "i": ("iː",),
        "u": ("uː",),
        # Modern RP's monophthongal SQUARE.
        "ɛː": ("eə",),
        "ɛə": ("eə",),
        # Syllabic consonants. Britfone writes these as schwa + consonant, and
        # we follow it, so that "bottle" is five phonemes whichever source it
        # comes from.
        "l̩": ("ə", "l"),
        "ɫ̩": ("ə", "l"),
        "n̩": ("ə", "n"),
        "m̩": ("ə", "m"),
    }
    table |= extra
    return table


EN_GB = AccentBuild(
    accent=accents.EN_GB,
    layers=(
        Layer(
            name="britfone",
            curated=True,
            symbols=_rp_symbols(britfone.SYMBOLS),
            separator=" ",
        ),
        Layer(
            name="wiktionary-en-GB",
            curated=True,
            # Lots of RP transcriptions on Wiktionary follow the newer
            # convention of /a/ for TRAP.
            symbols=_rp_symbols({"a": ("æ",)}),
        ),
        Layer(
            name="wiktionary-en-GB-untagged",
            curated=False,
            symbols=_rp_symbols({}),
            non_rhotic=True,
        ),
        Layer(
            name="espeak-en-GB-x-rp",
            curated=False,
            symbols=_rp_symbols(
                {
                    # espeak writes unstressed final schwa as ɐ, and has some
                    # segments that are more than one of our phonemes.
                    "ɐ": ("ə",),
                    "əl": ("ə", "l"),
                    "iə": ("ɪə",),
                    "aɪə": ("aɪ", "ə"),
                    "aʊə": ("aʊ", "ə"),
                    # ʲ marks a glide espeak inserts before a following vowel.
                    "ɪʲ": ("ɪ",),
                    "iːʲ": ("iː",),
                }
            ),
            separator="[_ ]",
            one_primary_stress=True,
            generate=lambda words: espeak.pronounce(sorted(words), voice="en-gb-x-rp"),
        ),
    ),
)

BUILDS = (EN_GB,)


def _happy_tensing(spelling: str, pronunciation: Pronunciation) -> Pronunciation:
    """Treat a final unstressed i-ish vowel in -y words as FLEECE.

    Sources disagree on happY: older RP transcriptions use KIT (/ˈhæpɪ/), newer
    ones a short /i/, which isn't contrastive and which we merge with FLEECE.
    Picking one makes "happy" the same five phonemes from every source.
    """
    if pronunciation[-1:] == ("ɪ",) and re.search(r"(y|ey|ie|i)$", spelling):
        return pronunciation[:-1] + ("iː",)
    return pronunciation


def _is_non_rhotic(pronunciation: Pronunciation, *, vowels: frozenset[str]) -> bool:
    return all(
        i + 1 < len(pronunciation) and pronunciation[i + 1] in vowels
        for i, p in enumerate(pronunciation)
        if p == "r"
    )


@dataclasses.dataclass
class LayerResult:
    pronunciations: dict[str, set[Pronunciation]]
    rejected: collections.Counter
    examples: dict[str, list[str]]


def _read_layer(
    layer: Layer, rows: list[tuple[str, str]], accent: accents.Accent
) -> LayerResult:
    result = LayerResult(collections.defaultdict(set), collections.Counter(), {})

    def reject(reason: str, example: str) -> None:
        result.rejected[reason] += 1
        result.examples.setdefault(reason, [])
        if len(result.examples[reason]) < 5:
            result.examples[reason].append(example)

    for word, transcription in rows:
        if layer.one_primary_stress and transcription.count("ˈ") > 1:
            reject("several primary stresses", f"{word} {transcription}")
            continue
        for variant in (
            [transcription] if layer.separator else ipa.variants(transcription)
        ):
            try:
                if layer.separator:
                    pronunciation = ipa.tokenize_segmented(
                        variant, separator=layer.separator, symbols=layer.symbols
                    )
                else:
                    pronunciation = ipa.tokenize(variant, symbols=layer.symbols)
            except ipa.UnknownSymbol as e:
                reject(f"unknown symbol {e.symbol!r}", f"{word} {transcription}")
                continue
            if not pronunciation:
                reject("empty", f"{word} {transcription}")
                continue
            pronunciation = _happy_tensing(word, pronunciation)
            if layer.non_rhotic and not _is_non_rhotic(
                pronunciation, vowels=accent.vowels()
            ):
                reject("rhotic", f"{word} {transcription}")
                continue
            result.pronunciations[word].add(pronunciation)
    return result


def _espeak_vocabulary(headwords: set[str]) -> set[str]:
    """Words worth having a pronunciation for, even a guessed one."""
    common = set()
    for word in wordfreq.iter_wordlist("en"):
        if wordfreq.zipf_frequency(word, "en") < ESPEAK_ZIPF:
            break
        if re.fullmatch(r"[a-z]{2,}", word):
            common.add(word)
    return common | {w for w in headwords if len(w) > 1}


def _answers(
    *,
    layers: tuple[Layer, ...],
    results: dict[str, LayerResult],
    chosen: dict[str, tuple[str, set[Pronunciation]]],
    zipf: dict[str, float],
    headwords: set[str],
    offensive: set[str],
) -> dict[int, list[Pronunciation]]:
    """Choose possible answers.

    An answer is a pronunciation of a common headword whose pronunciation
    comes from a curated layer. Every other non-generated layer that knows
    the word must agree, which catches errors and also rules out words like
    "reading", where Britfone includes the town's pronunciation. (Wiktionary
    lists the town separately.) No word with that pronunciation can be
    offensive, so that the reveal at the end can't be a slur.
    """
    curated = {layer.name for layer in layers if layer.curated}
    checkable = [layer.name for layer in layers if layer.generate is None]
    spellings_of = collections.defaultdict(set)
    for spelling, (_, prons) in chosen.items():
        for p in prons:
            spellings_of[p].add(spelling)

    answers = collections.defaultdict(set)
    for spelling, (layer_name, prons) in chosen.items():
        if (
            layer_name not in curated
            or spelling not in headwords
            or spelling in offensive
            or zipf[spelling] < ANSWER_ZIPF
        ):
            continue
        for p in prons:
            if len(p) not in ANSWER_LENGTHS:
                continue
            if any(
                spelling in results[name].pronunciations
                and p not in results[name].pronunciations[spelling]
                for name in checkable
            ):
                continue
            if spellings_of[p] & offensive:
                continue
            answers[len(p)].add(p)
    return {n: sorted(answers[n]) for n in ANSWER_LENGTHS}


def _build_accent(spec: AccentBuild, *, out: pathlib.Path) -> None:
    accent = spec.accent
    headwords = {w for (w,) in sourcefile.read("wiktionary-headwords")}
    offensive = {w for (w,) in sourcefile.read("wiktionary-offensive")}

    results: dict[str, LayerResult] = {}
    # spelling -> (layer name, pronunciations)
    chosen: dict[str, tuple[str, set[Pronunciation]]] = {}
    for layer in spec.layers:
        if layer.generate:
            missing = _espeak_vocabulary(headwords) - chosen.keys()
            rows = layer.generate(missing)
        else:
            rows = sourcefile.read(layer.name)
        result = _read_layer(layer, rows, accent)
        results[layer.name] = result
        added = 0
        for word, prons in result.pronunciations.items():
            if word not in chosen:
                chosen[word] = (layer.name, prons)
                added += 1
        print(
            f"{accent.tag} {layer.name}: {len(result.pronunciations)} words, "
            f"{added} new",
            file=sys.stderr,
        )
        for reason, count in result.rejected.most_common(15):
            print(
                f"  rejected {count}: {reason}, e.g. {result.examples[reason]}",
                file=sys.stderr,
            )

    zipf = {w: wordfreq.zipf_frequency(w, "en") for w in chosen}
    answers = _answers(
        layers=spec.layers,
        results=results,
        chosen=chosen,
        zipf=zipf,
        headwords=headwords,
        offensive=offensive,
    )
    for n, prons in answers.items():
        print(f"{accent.tag}: {len(prons)} answers of length {n}", file=sys.stderr)

    layer_index = {layer.name: i for i, layer in enumerate(spec.layers)}
    data = {
        "accent": {
            "tag": accent.tag,
            "name": accent.name,
            "phonemes": [
                {
                    "id": p.id,
                    "label": p.label,
                    "example": list(p.example),
                    "vowel": p.vowel,
                }
                for p in accent.phonemes
            ],
            "keyboard": [list(row) for row in accent.keyboard],
        },
        "sources": [layer.name for layer in spec.layers],
        # [spelling, Zipf frequency, source index, pronunciations,
        # headword], most frequent first. Pronunciations are phoneme ids
        # separated by spaces. Headword is 1 for a dictionary word, as opposed
        # to a name, abbreviation, etc.
        "words": [
            [
                spelling,
                round(zipf[spelling], 1),
                layer_index[layer_name],
                sorted(" ".join(p) for p in prons),
                int(spelling in headwords),
            ]
            for spelling, (layer_name, prons) in sorted(
                chosen.items(), key=lambda kv: (-zipf[kv[0]], kv[0])
            )
        ],
        "answers": {
            str(n): [" ".join(p) for p in prons] for n, prons in answers.items()
        },
    }
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{accent.tag}.json").write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )


def build(*, out: str) -> None:
    for spec in BUILDS:
        _build_accent(spec, out=pathlib.Path(out))
    accent_list = [{"tag": s.accent.tag, "name": s.accent.name} for s in BUILDS]
    (pathlib.Path(out) / "accents.json").write_text(
        json.dumps(accent_list, ensure_ascii=False), encoding="utf-8"
    )
