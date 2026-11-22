Below is the prompt I used to ask Opus 5.5 to write this game. (I didn't do so
by delivering this repo to it; I added this commit after the fact, honestly
mostly just to make it more convenient to review in the GitHub PR interface.)

# Phoneme game

Joshua Mandel’s Heardle is a version of Wordle using phonemes instead of letters. It's good! But I would like it to:

* Be extensible with accents, starting with BrE (default)
* Let me switch from the daily game to random games at any time
* In the same way that the app currently lets you type a word and see its phonemes, optionally show me the spellings of words I've guessed
* perhaps also show me possible completions as I type, regardless of whether I'm typing spellings or phonemes, with each completion showing its spellings or pronunciations as appropriate

I would like the UI to be in Elm and as offline as possible — ideally I can play this on the tube when I don't have signal.

Obviously there's a data processing pipeline that decides on the pronunciation dictionaries and has a build process separate from the UI / frontend. You can write that in whatever language you like. My understanding is that there is a Pareto frontier of quality vs coverage, so a solution that can layer different sources on top of each other with different priorities would be nice.

Provide a Nix package for the frontend. Maybe the data pipeline can be run from GitHub Actions, though it should be easy to run locally as well.

You'll also need to come up with a name. Go for a placeholder, or something relatively sober and descriptive that nevertheless isn't already the name of some other popular thing.

Use this page to describe your progress and any decisions that seem significant enough to want review. Good luck!
