import argparse

from sounding_data import build
from sounding_data.sources import britfone, wiktionary

FETCHERS = {"britfone": britfone.fetch, "wiktionary": wiktionary.fetch}


def main() -> None:
    parser = argparse.ArgumentParser(prog="sounding-data")
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

    args = parser.parse_args()
    if args.command == "fetch":
        for name in args.sources or FETCHERS:
            FETCHERS[name](refresh=args.refresh)
    else:
        build.build(out=args.out)


main()
