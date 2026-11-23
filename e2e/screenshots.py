"""Screenshot builds of the site in a range of states and window sizes.

This is for eyeballing layout changes, not for tests: nothing here passes or
fails. With --base, it screenshots that build too, and the gallery shows each
pair side by side, or once when they're identical.

    python e2e/screenshots.py --site result --base ../main/result --out shots

The clock is pinned, and each state is a saved game put in localStorage before
the page loads, so that both builds show exactly the same thing.
"""

import argparse
import asyncio
import dataclasses
import datetime
import functools
import http.server
import json
import pathlib
import threading
import typing

from playwright import async_api

DAY = datetime.date(2026, 1, 15)

SIZES = [
    (320, 568),
    (366, 615),
    (390, 664),
    (740, 360),
    (844, 390),
    (768, 1024),
    (1100, 900),
    (1366, 650),
]

# Light mode only at one size: the layout doesn't depend on it.
LIGHT_SIZE = (390, 664)

# Pronunciation keys, as stored in a saved game.
WISELY = "w aɪ z l iː"
MARSHAL = "m ɑː ʃ ə l"  # also martial, marshall
BERKELEY = "b ɑː k l iː"  # also barkley, barclay
KITTEN = "k ɪ t ə n"
TABLE = "t eɪ b ə l"
STROLL = "s t r əʊ l"
STREAM = "s t r iː m"
BOTTLE = "b ɒ t ə l"
ANSWER = "g l eɪ z d"  # glazed


@dataclasses.dataclass
class State:
    name: str
    length: int = 5
    guesses: list[str] = dataclasses.field(default_factory=list)
    answer: str = ANSWER
    lost: bool = False
    unlimited: bool = False
    then: typing.Callable[[async_api.Page], typing.Awaitable[None]] | None = None


STATES = [
    State("new"),
    State("playing", guesses=[WISELY, MARSHAL, BERKELEY]),
    State("won", guesses=[WISELY, MARSHAL, BERKELEY, ANSWER]),
    State(
        "lost",
        guesses=[WISELY, MARSHAL, BERKELEY, KITTEN, TABLE, STROLL],
        lost=True,
    ),
    State(
        "unlimited",
        guesses=[WISELY, MARSHAL, BERKELEY, KITTEN, TABLE, STROLL, STREAM, BOTTLE],
        unlimited=True,
    ),
    State(
        "six-sounds",
        length=6,
        guesses=["p l æ n ɪ t", "ɪ n s e k t"],
        answer="k r ɒ s ɪ ŋ",
    ),
    State("settings", then=lambda page: page.click("button[title=Settings]")),
    State("help", then=lambda page: page.click("button[title='How to play']")),
]


def saved(state: State) -> str:
    return json.dumps(
        {
            "settings": {
                "accent": "en-GB",
                "length": state.length,
                "showSpellings": True,
                "showCompletions": True,
                "showExamples": True,
                "theme": "auto",
                "unlimitedGuesses": state.unlimited,
            },
            "mode": "daily",
            "puzzleDay": DAY.isoformat(),
            "daily": {
                f"en-GB/{state.length}/{DAY.isoformat()}": {
                    "answer": state.answer,
                    "guesses": state.guesses,
                    "lost": state.lost,
                }
            },
            "free": {},
        }
    )


def serve(directory: pathlib.Path) -> str:
    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    handler = functools.partial(QuietHandler, directory=directory)
    server = http.server.ThreadingHTTPServer(("localhost", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f"http://localhost:{server.server_port}/"


@dataclasses.dataclass(frozen=True)
class Shot:
    state: str
    width: int
    height: int
    scheme: str

    @property
    def filename(self) -> str:
        return f"{self.state}-{self.width}x{self.height}-{self.scheme}.png"


def shots() -> list[tuple[Shot, State]]:
    return [
        (Shot(state.name, width, height, scheme), state)
        for state in STATES
        for (width, height) in SIZES
        for scheme in ["dark", "light"]
        if scheme == "dark" or (width, height) == LIGHT_SIZE
    ]


async def screenshot(
    browser: async_api.Browser,
    *,
    url: str,
    shot: Shot,
    state: State,
    path: pathlib.Path,
) -> None:
    context = await browser.new_context(
        service_workers="block",
        viewport={"width": shot.width, "height": shot.height},
        # Phones are high-DPI, and small text is hard to judge without it.
        device_scale_factor=2 if shot.width < 500 else 1,
        color_scheme=shot.scheme,
    )
    await context.add_init_script(
        f"localStorage.setItem('igzing /', {json.dumps(saved(state))})"
    )
    page = await context.new_page()
    await page.clock.set_fixed_time(datetime.datetime.combine(DAY, datetime.time(12)))
    await page.goto(url)
    await page.wait_for_selector("#board")
    if state.then:
        await state.then(page)
    await page.evaluate("document.fonts.ready")
    # Let the board's scroll to the latest guess happen.
    await page.wait_for_timeout(100)
    await page.screenshot(path=path, animations="disabled")
    await context.close()


async def screenshot_all(*, sites: dict[str, pathlib.Path], out: pathlib.Path) -> None:
    async with async_api.async_playwright() as playwright:
        browser = await playwright.chromium.launch()
        # Mostly waiting for pages to load, so worth doing several at once.
        slots = asyncio.Semaphore(8)

        async def one(**kwargs) -> None:
            async with slots:
                await screenshot(browser, **kwargs)

        jobs = []
        for name, site in sites.items():
            (out / name).mkdir(parents=True, exist_ok=True)
            url = serve(site)
            for shot, state in shots():
                jobs.append(
                    one(
                        url=url, shot=shot, state=state, path=out / name / shot.filename
                    )
                )
        await asyncio.gather(*jobs)
        await browser.close()


def img(shot: Shot, directory: str, alt: str) -> str:
    return (
        f'<img src="{directory}/{shot.filename}" width="{shot.width}"'
        f' loading="lazy" alt="{alt}">'
    )


def gallery(*, out: pathlib.Path, base: bool) -> str:
    sections = []
    changed = []
    for state in STATES:
        figures = []
        for shot, _ in shots():
            if shot.state != state.name:
                continue
            size = f"{shot.width}×{shot.height} {shot.scheme}"
            anchor = shot.filename.removesuffix(".png")

            if not base:
                body, caption = img(shot, "this", size), size
            elif (out / "base" / shot.filename).read_bytes() == (
                out / "this" / shot.filename
            ).read_bytes():
                body, caption = img(shot, "this", size), f"{size} (unchanged)"
            else:
                changed.append(f'<a href="#{anchor}">{state.name}, {size}</a>')
                body = (
                    '<div class="pair">'
                    + img(shot, "base", f"{size}, before")
                    + img(shot, "this", f"{size}, after")
                    + "</div>"
                )
                caption = f"{size}: before, after"
            figures.append(
                f'<figure id="{anchor}">{body}<figcaption>{caption}</figcaption></figure>'
            )
        sections.append(f"<h2>{state.name}</h2>\n" + "\n".join(figures))

    if not base:
        summary = ""
    elif changed:
        summary = (
            f"<p>{len(changed)} changed from the base build:</p><ul>"
            + "".join(f"<li>{link}</li>" for link in changed)
            + "</ul>"
        )
    else:
        summary = "<p>Nothing changed from the base build.</p>"

    return f"""<!DOCTYPE html>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Igzing screenshots</title>
<style>
  body {{ font-family: system-ui, sans-serif; background: #888; margin: 1rem; }}
  figure {{ display: inline-block; vertical-align: top; margin: 0 1rem 1rem 0; }}
  .pair {{ display: flex; gap: 0.5rem; }}
  img {{ max-width: 100%; height: auto; display: block; outline: 1px solid #000; }}
  figcaption {{ font-size: 0.8rem; }}
</style>
<h1>Igzing screenshots</h1>
{summary}
{"".join(sections)}
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--site", type=pathlib.Path, required=True)
    parser.add_argument("--base", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    args = parser.parse_args()

    sites = {"this": args.site} | ({"base": args.base} if args.base else {})
    asyncio.run(screenshot_all(sites=sites, out=args.out))
    (args.out / "index.html").write_text(gallery(out=args.out, base=bool(args.base)))


if __name__ == "__main__":
    main()
