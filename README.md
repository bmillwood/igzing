# Igzing

Guess the word by its sounds: a phonemic Wordle, starting with British
English. It works offline once loaded, so you can play it on the Underground.
Inspired by [Heardle](https://joshuamandel.com/heardle/), which does this for
American English with CMUdict.

The name, /ɪgzɪŋ/, is one of the most English-sounding five-phoneme non-words
we could find, according to a trigram model of the game's own dictionary.

- Choose between the **daily** puzzle and **random** games at any time; each
  keeps its own progress.
- **Type an ordinary word** to fill a row with its pronunciation, or use the
  phoneme keyboard. Each key shows an example word with the sound in bold.
- **Spellings** appear under each guess, and **suggestions** as you type,
  whether you're typing letters or sounds. Each can be turned off in settings.
- **4, 5 or 6 sounds** per word.
- **Unlimited guesses**, if you'd rather keep going until you get it.

## Layout

- `pipeline/igzing_data/`: the data pipeline (Python).
- `data/sources/`: the pipeline's fetched, normalised sources. These are
  committed.
- `frontend/`: the game (Elm), plus a small JS service worker for offline play.
- `default.nix`: `nix-build -A site` builds everything, data included, into a
  static site. `nix-build -A data` builds just the data.

## The data pipeline

It has two stages, so that the slow, networked, upstream-dependent part is
separate from the part that decides what the game contains:

1. **`fetch`** downloads each upstream source and extracts what we need into
   `data/sources/*.tsv`, as `word<TAB>transcription` in the source's own
   notation. Committing these means a source update arrives as a diff you can
   review. The `fetch` workflow does this monthly and opens a PR.

   ```sh
   nix-shell --run 'PYTHONPATH=pipeline python -m igzing_data fetch'
   ```

   Downloads are cached in `.cache/`. Wiktionary's is 530 MB, so pass
   `--refresh` only when you mean it.

2. **`build`** turns those into one JSON file per accent. It needs no network
   and is deterministic for a given nixpkgs, which is why the Nix build can run
   it.

   ```sh
   nix-shell --run 'PYTHONPATH=pipeline python -m igzing_data build --out _build/data'
   ```

   It prints how many words each layer contributed, and the transcriptions it
   rejected and why. That report is the first place to look when tuning.

### Layers

Each accent has a stack of pronunciation sources, best first (`build.py`). A
word takes its pronunciations from the **first layer that has any usable
pronunciation for it**, so a big, noisy source widens what counts as a valid
guess without overruling a careful one. For `en-GB`:

| Layer | Words | Notes |
| --- | --- | --- |
| [Britfone](https://github.com/JoseLlarena/Britfone) | 15k | Hand-checked SSBE. MIT. |
| Wiktionary, tagged RP/UK | +28k | Via [kaikki.org](https://kaikki.org). Skips Lindsey-style "British Southern Standard" notation and regional tags. |
| Wiktionary, untagged | +35k | Only for words with no tagged transcription. Rejects anything with a coda /r/. |
| espeak-ng `en-gb-x-rp` | +27k | Letter-to-sound rules, run at build time for common words the others lack. |

Every source has its own **symbol table** mapping its notation onto the
accent's 44 phonemes. An unmapped symbol rejects the transcription rather than
being skipped, so new notation gets counted instead of silently changing
phoneme counts.

### Answers

Answers are stricter than valid guesses. A word qualifies if:

- its pronunciation comes from a curated layer (Britfone or tagged
  Wiktionary);
- it's common (wordfreq Zipf ≥ 3);
- it's a Wiktionary headword in its own right, not only a plural, past tense,
  abbreviation or proper noun;
- every non-generated layer that knows the word agrees on the pronunciation;
- no word with that pronunciation has a sense tagged vulgar, offensive,
  derogatory or similar.

### Adding an accent

1. Add an `Accent` (phonemes, labels, example words, keyboard) to
   `accents.py`.
2. Add an `AccentTags` to `sources/wiktionary.py` if Wiktionary should
   contribute.
3. Add an `AccentBuild` with its layers to `build.py`.

General American, for instance, could use CMUdict, the US-tagged Wiktionary
layers, and espeak's `en-us`. The frontend reads the accent list from the
data, so it needs no changes.

## Developing the frontend

```sh
nix-shell
cd frontend
elm make src/Main.elm --output=elm.js
./assemble.sh elm.js ../_build/data ../_build/site
python -m http.server -d ../_build/site
elm-test
```

The tests in `e2e/` drive a built site in headless Chromium, for bugs that
only show up in a real browser. Run them from the repository root with
`pytest e2e`, which tests `result/` from `nix-build -A site` by default, or
another build with `IGZING_SITE=../_build/site pytest e2e` and the like.

`e2e/screenshots.py` screenshots a build in a range of states and window
sizes, and optionally another build to compare with, and makes a page to look
through them on. Every pull request's preview has one comparing it with its
base, at `pr/N/compare/screenshots/`.

`python -m igzing_data diff --base A --this B` describes how one build's data
differs from another's: answers, guessable words and pronunciations, most
frequent first. The data can change without `data/sources` changing, because
the pipeline's code and nixpkgs' espeak-ng and wordfreq matter too, so every
pull request gets this as well, in its preview comment and in full at
`pr/N/compare/data.txt`. To compare with the base, CI builds it with the
base's own nixpkgs.

After changing Elm dependencies, regenerate the Nix lock files:
`elm2nix convert > elm-srcs.nix && elm2nix snapshot`.

## Licences

The game's word data derives from Wiktionary (CC BY-SA 4.0) and wordfreq's
lists (CC BY-SA 4.0), so the built data files are CC BY-SA 4.0. They also
derive from Britfone, whose MIT licence, `data/sources/britfone-LICENSE.txt`,
asks that its notice go with it, so the built site includes that file too.
