module DictionaryTest exposing (suite)

import Dictionary exposing (Dictionary)
import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)


{-| A small dictionary in the data file's format, with words and
pronunciations in order, as the pipeline writes them.
-}
dictionary : Result D.Error Dictionary
dictionary =
    D.decodeString Dictionary.decoder """
    {
      "accent": {"tag": "xx", "name": "Test", "phonemes": [], "keyboard": []},
      "sources": ["test"],
      "words": [
        ["chin", 4.0, 0, 1, [4]],
        ["tea", 5.0, 0, 1, [0]],
        ["tee", 3.0, 0, 1, [0]],
        ["tin", 4.5, 0, 1, [2]],
        ["ting", 5.0, 0, 0, [3]],
        ["to", 6.0, 0, 1, [1]]
      ],
      "pronunciations": [
        ["t iː", [1, 2]],
        ["t uː", [5]],
        ["t ɪ n", [3]],
        ["t ɪ ŋ", [4]],
        ["tʃ ɪ n", [0]]
      ],
      "answers": {}
    }
    """


suite : Test
suite =
    -- Lookups are by hand-written binary search over sorted arrays, which
    -- is easy to get off by one, especially at the ends.
    describe "Dictionary"
        [ test "finds every word, including the first and last, and no others" <|
            \_ ->
                dictionary
                    |> Result.map
                        (\dict ->
                            List.map (\s -> Dictionary.pronunciationsOf dict 2 s |> Maybe.map Tuple.second)
                                [ "chin", "to", "tea", "a", "zzz", "te" ]
                        )
                    |> Expect.equal (Ok [ Just [], Just [ "t uː" ], Just [ "t iː" ], Nothing, Nothing, Nothing ])
        , test "finds a pronunciation's words, best first" <|
            \_ ->
                dictionary
                    |> Result.map (\dict -> Dictionary.spellingsOf dict "t iː")
                    |> Expect.equal (Ok [ "tea", "tee" ])
        , test "completes pronunciations at phoneme boundaries, so t isn't a prefix of tʃ" <|
            \_ ->
                dictionary
                    |> Result.map (\dict -> Dictionary.completePronunciation dict 3 6 [ "t" ] |> Tuple.mapFirst (List.map .key))
                    |> Expect.equal (Ok ( [ "t ɪ n", "t ɪ ŋ" ], 2 ))
        , test "completes spellings, dictionary words first, then by frequency" <|
            \_ ->
                dictionary
                    |> Result.map (\dict -> Dictionary.completeSpelling dict 3 6 "ti" |> List.map (Tuple.first >> .spelling))
                    |> Expect.equal (Ok [ "tin", "ting" ])
        ]
