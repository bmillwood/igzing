module Game exposing
    ( Game
    , Mark(..)
    , Status(..)
    , dailyIndex
    , decoder
    , encode
    , hints
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


{-| What the guesses so far show about where a phoneme could go in the
next guess, square by square, so that the square is:

  - `Just Correct` where the phoneme is known to be,
  - `Just Present` where it's known not to be, and some copy of it hasn't been
    placed yet,
  - `Just Absent` where it's known not to be, and no copy is known to be left
    over to place,
  - `Nothing` where it might be.

A square is known not to hold the phoneme if the phoneme has been tried there,
if another phoneme is known to be there, or if every copy in the answer is
accounted for already.

-}
hints : (String -> List String) -> Game -> String -> List (Maybe Mark)
hints toPhonemes game phoneme =
    let
        answer =
            toPhonemes game.answer

        -- Each guess's marks for this phoneme, by square.
        tries =
            List.map
                (\guess ->
                    let
                        guessed =
                            toPhonemes guess
                    in
                    List.map3 (\square p mark -> ( square, p, mark ))
                        (List.range 0 (List.length guessed - 1))
                        guessed
                        (score answer guessed)
                )
                game.guesses

        triesOfPhoneme =
            List.map (List.filter (\( _, p, _ ) -> p == phoneme)) tries

        -- Squares known to hold some phoneme, which might be this one.
        knownSquares =
            List.concat tries
                |> List.filterMap
                    (\( square, p, mark ) ->
                        if mark == Correct then
                            Just ( square, p )

                        else
                            Nothing
                    )
                |> Dict.fromList

        placed =
            Dict.values knownSquares |> List.filter ((==) phoneme) |> List.length

        -- A guess with n non-Absent copies shows the answer has at least n,
        -- and if it also has an Absent copy, exactly n.
        found try =
            List.length (List.filter (\( _, _, mark ) -> mark /= Absent) try)

        atLeast =
            List.maximum (List.map found triesOfPhoneme) |> Maybe.withDefault 0

        copiesLeftOver =
            atLeast > placed

        allAccountedFor =
            List.any (List.any (\( _, _, mark ) -> mark == Absent)) triesOfPhoneme
                && not copiesLeftOver

        triedAt square =
            List.any (List.any (\( s, _, _ ) -> s == square)) triesOfPhoneme

        hint square =
            case Dict.get square knownSquares of
                Just p ->
                    if p == phoneme then
                        Just Correct

                    else
                        Just notHere

                Nothing ->
                    if triedAt square || allAccountedFor then
                        Just notHere

                    else
                        Nothing

        notHere =
            if copiesLeftOver then
                Present

            else
                Absent
    in
    List.map hint (List.range 0 (List.length answer - 1))


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
