import pathlib
import shutil
import sys
import urllib.parse
import urllib.request

CACHE = pathlib.Path(".cache")


def cached(url: str, *, refresh: bool) -> pathlib.Path:
    """Download url into the cache directory, unless it's already there."""
    path = CACHE / pathlib.PurePosixPath(urllib.parse.urlparse(url).path).name
    if refresh or not path.exists():
        print(f"downloading {url}", file=sys.stderr)
        CACHE.mkdir(exist_ok=True)
        partial = path.with_suffix(path.suffix + ".partial")
        with urllib.request.urlopen(url) as response, partial.open("wb") as out:
            shutil.copyfileobj(response, out)
        partial.rename(path)
    return path
