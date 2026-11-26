module Dictionary exposing
    ( Accent
    , AccentInfo
    , Dictionary
    , Entry
    , Phoneme
    , Word
    , accentsDecoder
    , answers
    , completePronunciation
    , completeSpelling
    , decoder
    , entry
    , label
    , pronunciationsOf
    , spellingsOf
    , toPhonemes
    )

{-| The pronunciation dictionary for one accent, as built by the data pipeline.

Pronunciations are kept as their phoneme ids joined with spaces (a `key`),
which is also how the data file writes them.

-}

import Array exposing (Array)
import Dict exposing (Dict)
import Json.Decode as D


type alias AccentInfo =
    { tag : String
    , name : String
    }


type alias Phoneme =
    { id : String
    , label : String
    , example : ( String, String, String )
    , vowel : Bool
    }


type alias Accent =
    { tag : String
    , name : String
    , phonemes : List Phoneme
    , keyboard : List (List String)
    }


type alias Word =
    { spelling : String
    , zipf : Float
    , source : String
    , pronunciations : List String

    -- A dictionary word, rather than a name, abbreviation, etc.
    , headword : Bool

    -- For ordering suggestions: headwords first, then by frequency
    , rank : Float
    }


{-| Everything known about one pronunciation.
-}
type alias Entry =
    { key : String

    -- Best ranked first
    , words : List Word
    , rank : Float
    }


{-| The words and entries are sorted by spelling and key respectively, as
JavaScript compares strings, as the data file has them. They're looked up by
binary search, because building a Dict of a hundred thousand words, or
anything else that's more work than reading them in, takes long enough to
notice on a phone, every time the game opens.
-}
type alias Dictionary =
    { accent : Accent
    , labels : Dict String String
    , words : Array Word
    , entries : Array Entry
    , answers : Dict Int (Array String)
    }


accentsDecoder : D.Decoder (List AccentInfo)
accentsDecoder =
    D.list
        (D.map2 AccentInfo
            (D.field "tag" D.string)
            (D.field "name" D.string)
        )


decoder : D.Decoder Dictionary
decoder =
    D.map5 build
        (D.field "accent" accentDecoder)
        (D.field "sources" (D.array D.string))
        (D.field "words" (D.array rawWordDecoder))
        (D.field "pronunciations" (D.array (D.map2 Tuple.pair (D.index 0 D.string) (D.index 1 (D.list D.int)))))
        (D.field "answers" (D.dict (D.array D.string)))


{-| A word, with its pronunciations as indices into the data file's list.
-}
type alias RawWord =
    { spelling : String, zipf : Float, source : Int, headword : Bool, pronunciations : List Int }


rawWordDecoder : D.Decoder RawWord
rawWordDecoder =
    D.map5 RawWord
        (D.index 0 D.string)
        (D.index 1 D.float)
        (D.index 2 D.int)
        (D.index 3 (D.map ((==) 1) D.int))
        (D.index 4 (D.list D.int))


accentDecoder : D.Decoder Accent
accentDecoder =
    D.map4 Accent
        (D.field "tag" D.string)
        (D.field "name" D.string)
        (D.field "phonemes"
            (D.list
                (D.map4 Phoneme
                    (D.field "id" D.string)
                    (D.field "label" D.string)
                    (D.field "example"
                        (D.map3 (\a b c -> ( a, b, c ))
                            (D.index 0 D.string)
                            (D.index 1 D.string)
                            (D.index 2 D.string)
                        )
                    )
                    (D.field "vowel" D.bool)
                )
            )
        )
        (D.field "keyboard" (D.list (D.list D.string)))


build : Accent -> Array String -> Array RawWord -> Array ( String, List Int ) -> Dict String (Array String) -> Dictionary
build accent sources rawWords rawEntries rawAnswers =
    let
        keys =
            Array.map Tuple.first rawEntries

        words =
            Array.map
                (\w ->
                    { spelling = w.spelling
                    , zipf = w.zipf
                    , source = Array.get w.source sources |> Maybe.withDefault "?"
                    , pronunciations = List.filterMap (\i -> Array.get i keys) w.pronunciations
                    , headword = w.headword
                    , rank =
                        if w.headword then
                            w.zipf + 1000

                        else
                            w.zipf
                    }
                )
                rawWords
    in
    { accent = accent
    , labels = Dict.fromList (List.map (\p -> ( p.id, p.label )) accent.phonemes)
    , words = words
    , entries =
        Array.map
            (\( key, indices ) ->
                let
                    entryWords =
                        List.filterMap (\i -> Array.get i words) indices
                in
                { key = key
                , words = entryWords
                , rank = List.head entryWords |> Maybe.map .rank |> Maybe.withDefault 0
                }
            )
            rawEntries
    , answers =
        Dict.foldl
            (\k v acc ->
                case String.toInt k of
                    Just n ->
                        Dict.insert n v acc

                    Nothing ->
                        acc
            )
            Dict.empty
            rawAnswers
    }


{-| The index of the first element whose key isn't less than the target, in
an array sorted by key.
-}
lowerBound : (a -> String) -> String -> Array a -> Int
lowerBound toKey target array =
    let
        -- The answer is in [low, high].
        go low high =
            if low >= high then
                low

            else
                let
                    middle =
                        (low + high) // 2
                in
                case Array.get middle array of
                    Just x ->
                        if toKey x < target then
                            go (middle + 1) high

                        else
                            go low middle

                    Nothing ->
                        low
    in
    go 0 (Array.length array)


find : (a -> String) -> String -> Array a -> Maybe a
find toKey target array =
    Array.get (lowerBound toKey target array) array
        |> Maybe.andThen
            (\x ->
                if toKey x == target then
                    Just x

                else
                    Nothing
            )


{-| The elements whose keys start with the prefix, in order, in an array
sorted by key.
-}
startingWith : (a -> String) -> String -> Array a -> List a
startingWith toKey prefix array =
    let
        go i acc =
            case Array.get i array of
                Just x ->
                    if String.startsWith prefix (toKey x) then
                        go (i + 1) (x :: acc)

                    else
                        List.reverse acc

                Nothing ->
                    List.reverse acc
    in
    go (lowerBound toKey prefix array) []


toPhonemes : String -> List String
toPhonemes key =
    if key == "" then
        []

    else
        String.split " " key


label : Dictionary -> String -> String
label dict id =
    Dict.get id dict.labels |> Maybe.withDefault id


entry : Dictionary -> String -> Maybe Entry
entry dict key =
    find .key key dict.entries


spellingsOf : Dictionary -> String -> List String
spellingsOf dict key =
    entry dict key |> Maybe.map (.words >> List.map .spelling) |> Maybe.withDefault []


{-| Pronunciations of a spelling with the given number of phonemes.
-}
pronunciationsOf : Dictionary -> Int -> String -> Maybe ( Word, List String )
pronunciationsOf dict length spelling =
    find .spelling (String.toLower spelling) dict.words
        |> Maybe.map
            (\w ->
                ( w
                , List.filter (\p -> List.length (toPhonemes p) == length) w.pronunciations
                )
            )


answers : Dictionary -> Int -> Array String
answers dict length =
    Dict.get length dict.answers |> Maybe.withDefault Array.empty


{-| Words starting with the given text that have a pronunciation of the given
length, best ranked first.
-}
completeSpelling : Dictionary -> Int -> Int -> String -> List ( Word, String )
completeSpelling dict length limit prefix =
    startingWith .spelling (String.toLower prefix) dict.words
        |> List.concatMap
            (\w ->
                List.filter (\p -> List.length (toPhonemes p) == length) w.pronunciations
                    |> List.map (Tuple.pair w)
            )
        |> List.sortBy (\( w, _ ) -> -w.rank)
        |> List.take limit


{-| Pronunciations of the given length starting with the given phonemes, best
ranked first, along with how many there are in total.
-}
completePronunciation : Dictionary -> Int -> Int -> List String -> ( List Entry, Int )
completePronunciation dict length limit prefix =
    let
        key =
            String.join " " prefix

        -- Keys starting with "t" include "tʃ …", so check that the prefix
        -- ends at a phoneme boundary.
        matches =
            startingWith .key key dict.entries
                |> List.filter
                    (\e ->
                        (e.key == key || String.startsWith (key ++ " ") e.key)
                            && List.length (toPhonemes e.key)
                            == length
                    )
                |> List.sortBy (\e -> -e.rank)
    in
    ( List.take limit matches, List.length matches )
