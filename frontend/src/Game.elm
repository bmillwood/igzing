module Game exposing
    ( Game
    , Mark(..)
    , Status(..)
    , dailyIndex
    , decoder
    , encode
    , keyMarks
    , maxGuesses
    , score
    , status
    )

import Bitwise
import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E


maxGuesses : Int
maxGuesses =
    6


{-| A game in progress or finished. The answer and guesses are pronunciation
keys (phoneme ids joined by spaces). The answer is stored rather than
recomputed, so that a data update can't change a game partway through.
-}
type alias Game =
    { answer : String
    , guesses : List String
    }


type Mark
    = Correct
    | Present
    | Absent


type Status
    = Playing
    | Won
    | Lost


status : Game -> Status
status game =
    if List.member game.answer game.guesses then
        Won

    else if List.length game.guesses >= maxGuesses then
        Lost

    else
        Playing


{-| Wordle's rules: exact matches first, then each remaining answer phoneme
can make at most one other guessed occurrence of it Present, left to right.
-}
score : List String -> List String -> List Mark
score answer guess =
    let
        pairs =
            List.map2 Tuple.pair answer guess

        unmatched =
            List.foldl
                (\( a, g ) counts ->
                    if a == g then
                        counts

                    else
                        Dict.update a (\n -> Just (Maybe.withDefault 0 n + 1)) counts
                )
                Dict.empty
                pairs

        step ( a, g ) ( marks, counts ) =
            if a == g then
                ( Correct :: marks, counts )

            else
                case Dict.get g counts of
                    Just n ->
                        if n > 0 then
                            ( Present :: marks, Dict.insert g (n - 1) counts )

                        else
                            ( Absent :: marks, counts )

                    Nothing ->
                        ( Absent :: marks, counts )
    in
    List.foldl step ( [], unmatched ) pairs
        |> Tuple.first
        |> List.reverse


{-| The best mark each phoneme has had so far, for colouring the keyboard.
-}
keyMarks : (String -> List String) -> Game -> Dict String Mark
keyMarks toPhonemes game =
    let
        rank mark =
            case mark of
                Correct ->
                    2

                Present ->
                    1

                Absent ->
                    0

        better new old =
            case old of
                Just o ->
                    if rank o >= rank new then
                        o

                    else
                        new

                Nothing ->
                    new
    in
    List.foldl
        (\guess acc ->
            let
                phonemes =
                    toPhonemes guess
            in
            List.map2 Tuple.pair phonemes (score (toPhonemes game.answer) phonemes)
                |> List.foldl (\( p, m ) acc2 -> Dict.insert p (better m (Dict.get p acc2)) acc2) acc
        )
        Dict.empty
        game.guesses


{-| Which answer to use on a given day, from a 32-bit FNV-1a hash of the date
and game settings, so that everyone with the same data gets the same answer
without needing a server.
-}
dailyIndex : String -> Int -> Int
dailyIndex seed count =
    let
        -- 16777619 is 2^24 + 403; splitting the multiplication keeps the
        -- intermediate results within a double's exact integer range.
        multiply h =
            Bitwise.shiftRightZfBy 0 (Bitwise.shiftLeftBy 24 h + h * 403)

        hash =
            String.foldl
                (\c h -> multiply (Bitwise.shiftRightZfBy 0 (Bitwise.xor h (Char.toCode c))))
                2166136261
                seed
    in
    if count <= 0 then
        0

    else
        modBy count hash


encode : Game -> E.Value
encode game =
    E.object
        [ ( "answer", E.string game.answer )
        , ( "guesses", E.list E.string game.guesses )
        ]


decoder : D.Decoder Game
decoder =
    D.map2 Game
        (D.field "answer" D.string)
        (D.field "guesses" (D.list D.string))
