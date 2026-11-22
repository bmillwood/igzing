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
    , phonemes : List String

    -- Best ranked first
    , words : List Word
    , rank : Float
    }


type alias Dictionary =
    { accent : Accent
    , labels : Dict String String

    -- Best ranked first
    , words : List Word
    , bySpelling : Dict String Word
    , byPronunciation : Dict String Entry

    -- Entries of each length, best ranked first
    , byLength : Dict Int (List Entry)
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
    D.map4 build
        (D.field "accent" accentDecoder)
        (D.field "sources" (D.array D.string))
        (D.field "words" (D.list rawWordDecoder))
        (D.field "answers" (D.dict (D.array D.string)))


type alias RawWord =
    { spelling : String, zipf : Float, source : Int, pronunciations : List String, headword : Bool }


rawWordDecoder : D.Decoder RawWord
rawWordDecoder =
    D.map5 RawWord
        (D.index 0 D.string)
        (D.index 1 D.float)
        (D.index 2 D.int)
        (D.index 3 (D.list D.string))
        (D.index 4 (D.map ((==) 1) D.int))


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


build : Accent -> Array String -> List RawWord -> Dict String (Array String) -> Dictionary
build accent sources rawWords rawAnswers =
    let
        words =
            List.map
                (\w ->
                    { spelling = w.spelling
                    , zipf = w.zipf
                    , source = Array.get w.source sources |> Maybe.withDefault "?"
                    , pronunciations = w.pronunciations
                    , headword = w.headword
                    , rank =
                        if w.headword then
                            w.zipf + 1000

                        else
                            w.zipf
                    }
                )
                rawWords
                |> List.sortBy (\w -> -w.rank)

        -- Folding from the right and consing keeps each entry's words in
        -- order.
        byPronunciation =
            List.foldr
                (\w acc ->
                    List.foldl
                        (\p acc2 ->
                            Dict.update p
                                (\existing ->
                                    case existing of
                                        Just e ->
                                            Just { e | words = w :: e.words, rank = max e.rank w.rank }

                                        Nothing ->
                                            Just { key = p, phonemes = String.split " " p, words = [ w ], rank = w.rank }
                                )
                                acc2
                        )
                        acc
                        w.pronunciations
                )
                Dict.empty
                words

        byLength =
            Dict.values byPronunciation
                |> List.sortBy (\e -> -e.rank)
                |> List.foldr
                    (\e acc ->
                        Dict.update (List.length e.phonemes)
                            (\es -> Just (e :: Maybe.withDefault [] es))
                            acc
                    )
                    Dict.empty
    in
    { accent = accent
    , labels = Dict.fromList (List.map (\p -> ( p.id, p.label )) accent.phonemes)
    , words = words
    , bySpelling = Dict.fromList (List.map (\w -> ( w.spelling, w )) words)
    , byPronunciation = byPronunciation
    , byLength = byLength
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
    Dict.get key dict.byPronunciation


spellingsOf : Dictionary -> String -> List String
spellingsOf dict key =
    entry dict key |> Maybe.map (.words >> List.map .spelling) |> Maybe.withDefault []


{-| Pronunciations of a spelling with the given number of phonemes.
-}
pronunciationsOf : Dictionary -> Int -> String -> Maybe ( Word, List String )
pronunciationsOf dict length spelling =
    Dict.get (String.toLower spelling) dict.bySpelling
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
    let
        lower =
            String.toLower prefix

        go remaining ws acc =
            if remaining <= 0 then
                List.reverse acc

            else
                case ws of
                    [] ->
                        List.reverse acc

                    w :: rest ->
                        if String.startsWith lower w.spelling then
                            let
                                matching =
                                    List.filter (\p -> List.length (toPhonemes p) == length) w.pronunciations
                                        |> List.map (Tuple.pair w)
                            in
                            go (remaining - List.length matching) rest (List.reverse matching ++ acc)

                        else
                            go remaining rest acc
    in
    go limit dict.words [] |> List.take limit


{-| Pronunciations of the given length starting with the given phonemes, best
ranked first, along with how many there are in total.
-}
completePronunciation : Dictionary -> Int -> Int -> List String -> ( List Entry, Int )
completePronunciation dict length limit prefix =
    let
        n =
            List.length prefix

        matches =
            Dict.get length dict.byLength
                |> Maybe.withDefault []
                |> List.filter (\e -> List.take n e.phonemes == prefix)
    in
    ( List.take limit matches, List.length matches )
