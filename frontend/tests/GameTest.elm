module GameTest exposing (suite)

import Expect
import Game exposing (Mark(..))
import Json.Decode as D
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Game"
        [ describe "score"
            -- Repeated phonemes are where Wordle-style scoring usually goes
            -- wrong.
            [ test "an exact match uses up the answer's only copy, so an earlier repeat is Absent" <|
                \_ ->
                    Game.score [ "k", "æ", "t" ] [ "t", "æ", "t" ]
                        |> Expect.equal [ Absent, Correct, Correct ]
            , test "only as many Presents as the answer has copies" <|
                \_ ->
                    Game.score [ "s", "ɪ", "t" ] [ "t", "t", "ɪ" ]
                        |> Expect.equal [ Present, Absent, Present ]
            , test "a repeated answer phoneme can make two guessed copies Present" <|
                \_ ->
                    Game.score [ "t", "ɪ", "t", "ə", "l" ] [ "ə", "t", "l", "ɪ", "t" ]
                        |> Expect.equal [ Present, Present, Present, Present, Present ]
            ]
        , test "a game saved before unlimited guesses, out of guesses, stays lost" <|
            \_ ->
                D.decodeString Game.decoder """{"answer": "a", "guesses": ["b", "b", "b", "b", "b", "b"]}"""
                    |> Result.map Game.status
                    |> Expect.equal (Ok Game.Lost)
        , test "dailyIndex is 32-bit FNV-1a, so changing it would change everyone's daily answer" <|
            \_ ->
                -- Reference value from Python:
                --   h = 2166136261
                --   for c in b"en-GB/5/2026-11-20": h = ((h ^ c) * 16777619) % 2**32
                Game.dailyIndex "en-GB/5/2026-11-20" 4294967296
                    |> Expect.equal 1317845505
        ]
