"""eSpeak NG's letter-to-sound rules and exception lists. GPL-3.0.

Unlike the other sources, this is run at build time over whatever words the
better sources don't cover, so its output isn't committed. The result depends
on the espeak-ng version, which Nix pins.
"""

import subprocess


def pronounce(words: list[str], *, voice: str) -> list[tuple[str, str]]:
    # A full stop after each word makes espeak treat it as a separate
    # sentence, giving the stressed citation form on its own line.
    result = subprocess.run(
        ["espeak-ng", "-v", voice, "-q", "--ipa", "--sep=_"],
        input="".join(f"{w}.\n" for w in words),
        capture_output=True,
        text=True,
        check=True,
    )
    lines = result.stdout.splitlines()
    assert len(lines) == len(words), (len(lines), len(words))
    return [(w, line.strip()) for w, line in zip(words, lines)]
