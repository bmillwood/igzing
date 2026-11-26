import argparse
import pathlib

from igzing_data import build, diff
from igzing_data.sources import britfone, wiktionary

FETCHERS = {"britfone": britfone.fetch, "wiktionary": wiktionary.fetch}


def main() -> None:
    parser = argparse.ArgumentParser(prog="igzing-data")
    commands = parser.add_subparsers(dest="command", required=True)

    fetch = commands.add_parser(
        "fetch", help="download upstream sources into data/sources"
    )
    fetch.add_argument("sources", nargs="*", choices=list(FETCHERS))
    fetch.add_argument(
        "--refresh", action="store_true", help="ignore previously downloaded files"
    )

    build_parser = commands.add_parser(
        "build", help="build the game's data files from data/sources"
    )
    build_parser.add_argument("--out", required=True)

    diff_parser = commands.add_parser(
        "diff", help="describe how one build's data differs from another's"
    )
    diff_parser.add_argument("--base", type=pathlib.Path, required=True)
    diff_parser.add_argument("--this", type=pathlib.Path, required=True)
    diff_parser.add_argument(
        "--limit", type=int, help="list at most this many items of each kind"
    )

    args = parser.parse_args()
    if args.command == "fetch":
        for name in args.sources or FETCHERS:
            FETCHERS[name](refresh=args.refresh)
    elif args.command == "build":
        build.build(out=args.out)
    else:
        print(diff.report(base=args.base, this=args.this, limit=args.limit), end="")


main()
