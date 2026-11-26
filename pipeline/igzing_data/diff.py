"""Compare two builds of the game's data, as Markdown for a pull request.

The data can change without data/sources changing, because the build also
depends on the pipeline's code and on nixpkgs (espeak-ng, wordfreq). This
reports what the game would actually do differently, whatever the cause.
"""

import collections
import dataclasses
import json
import pathlib


@dataclasses.dataclass(frozen=True)
class Word:
    zipf: float
    source: str
    pronunciations: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class AccentData:
    raw: dict
    words: dict[str, Word]
    # pronunciation -> spellings, most frequent first
    spellings: dict[str, list[str]]

    @classmethod
    def load(cls, path: pathlib.Path) -> "AccentData":
        raw = json.loads(path.read_text(encoding="utf-8"))
        words = {
            spelling: Word(
                zipf=zipf, source=raw["sources"][source], pronunciations=tuple(prons)
            )
            for spelling, zipf, source, prons, _headword in raw["words"]
        }
        spellings = collections.defaultdict(list)
        for spelling, word in words.items():
            for pron in word.pronunciations:
                spellings[pron].append(spelling)
        return cls(raw=raw, words=words, spellings=spellings)


def _tags(data: pathlib.Path) -> list[str]:
    accents = json.loads((data / "accents.json").read_text(encoding="utf-8"))
    return [accent["tag"] for accent in accents]


def _capped(lines: list[str], *, limit: int | None) -> list[str]:
    if limit is None or len(lines) <= limit:
        return lines
    return lines[:limit] + [f"- … and {len(lines) - limit:,} more"]


def _details(summary: str, lines: list[str], *, limit: int | None) -> list[str]:
    if not lines:
        return []
    return [
        f"<details><summary>{summary}</summary>",
        "",
        *_capped(lines, limit=limit),
        "",
        "</details>",
        "",
    ]


def _pron(pron: str) -> str:
    return f"/{pron}/"


def _accent_report(
    tag: str, *, base: AccentData, this: AccentData, limit: int | None
) -> list[str]:
    facts = []
    sections = []

    if base.raw["accent"] != this.raw["accent"]:
        facts.append("its phonemes, labels or keyboard changed")
    if base.raw["sources"] != this.raw["sources"]:
        facts.append(
            f"its layers changed from {', '.join(base.raw['sources'])}"
            f" to {', '.join(this.raw['sources'])}"
        )

    answers_changed = False
    for length in sorted(base.raw["answers"].keys() | this.raw["answers"].keys()):
        before = set(base.raw["answers"].get(length, []))
        after = set(this.raw["answers"].get(length, []))
        if before == after:
            continue
        answers_changed = True
        added, removed = after - before, before - after
        facts.append(
            f"{length}-sound answers {len(before):,} → {len(after):,}"
            f" (+{len(added):,} −{len(removed):,})"
        )

        def line(sign: str, pron: str, data: AccentData) -> tuple[float, str]:
            spellings = data.spellings[pron]
            zipf = max(data.words[s].zipf for s in spellings)
            return (-zipf, f"- {sign} {_pron(pron)} {', '.join(spellings)}")

        lines = sorted(
            [line("+", p, this) for p in added] + [line("−", p, base) for p in removed]
        )
        sections += _details(
            f"{length}-sound answers, most frequent first",
            [text for _, text in lines],
            limit=limit,
        )

    added = this.words.keys() - base.words.keys()
    removed = base.words.keys() - this.words.keys()
    if added or removed:
        facts.append(
            f"guessable words {len(base.words):,} → {len(this.words):,}"
            f" (+{len(added):,} −{len(removed):,})"
        )
    lines = sorted(
        [(-this.words[w].zipf, w, "+", this.words[w]) for w in added]
        + [(-base.words[w].zipf, w, "−", base.words[w]) for w in removed]
    )
    sections += _details(
        "Guessable words, most frequent first",
        [
            f"- {sign} {w} {', '.join(map(_pron, word.pronunciations))} ({word.source})"
            for _, w, sign, word in lines
        ],
        limit=limit,
    )

    changed = sorted(
        (-this.words[w].zipf, w)
        for w in this.words.keys() & base.words.keys()
        if this.words[w].pronunciations != base.words[w].pronunciations
    )
    if changed:
        facts.append(f"{len(changed):,} words' pronunciations changed")

    def change(w: str) -> str:
        old, new = base.words[w], this.words[w]
        sources = (
            f" ({new.source})"
            if old.source == new.source
            else f" ({old.source} → {new.source})"
        )
        return (
            f"- {w}: {', '.join(map(_pron, old.pronunciations))}"
            f" → {', '.join(map(_pron, new.pronunciations))}{sources}"
        )

    sections += _details(
        "Changed pronunciations, most frequent first",
        [change(w) for _, w in changed],
        limit=limit,
    )

    if not facts:
        # The file differs, but in nothing reported above: frequencies, say.
        facts.append("nothing changed that this report looks at")
    summary = f"**{tag}:** " + "; ".join(facts) + "."
    if answers_changed:
        # The daily answer is a hash of the date modulo the number of answers,
        # indexing into the sorted list, so almost any change moves them all.
        summary += " Daily puzzles from now on will be different."
    return [summary, "", *sections]


def report(*, base: pathlib.Path, this: pathlib.Path, limit: int | None) -> str:
    base_tags, this_tags = _tags(base), _tags(this)
    lines = []
    for tag in this_tags:
        if tag not in base_tags:
            lines += [f"**{tag}:** new.", ""]
        elif (base / f"{tag}.json").read_bytes() != (this / f"{tag}.json").read_bytes():
            lines += _accent_report(
                tag,
                base=AccentData.load(base / f"{tag}.json"),
                this=AccentData.load(this / f"{tag}.json"),
                limit=limit,
            )
    for tag in base_tags:
        if tag not in this_tags:
            lines += [f"**{tag}:** removed.", ""]
    if not lines:
        return "The game's data is unchanged.\n"
    return "\n".join(lines)
