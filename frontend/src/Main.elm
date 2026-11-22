port module Main exposing (main)

import Array
import Browser
import Browser.Dom
import Browser.Events
import Dict exposing (Dict)
import Dictionary exposing (Dictionary)
import Game exposing (Game)
import Html exposing (Html)
import Html.Attributes as A
import Html.Events as E
import Html.Keyed
import Http
import Json.Decode as D
import Json.Encode as JE
import Random
import Task
import Time


port save : JE.Value -> Cmd msg


port share : String -> Cmd msg


port shared : (String -> msg) -> Sub msg


main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = updateAndSave
        , view = view
        , subscriptions = subscriptions
        }



-- MODEL


type alias Settings =
    { accent : String
    , length : Int
    , showSpellings : Bool
    , showCompletions : Bool
    , showExamples : Bool
    }


type Mode
    = Daily
    | Free


type Panel
    = SettingsPanel
    | HelpPanel


type Load a
    = Loading
    | Failed String
    | Loaded a


type alias Model =
    { settings : Settings
    , mode : Mode
    , today : Maybe String

    -- The date of the daily puzzle being shown. It lags behind today while
    -- you finish a puzzle you started before midnight.
    , puzzleDay : Maybe String
    , accents : Load (List Dictionary.AccentInfo)
    , dictionaries : Dict String (Load Dictionary)

    -- Games by gameKey
    , daily : Dict String Game
    , free : Dict String Game

    -- The guess being entered, as phoneme ids
    , row : List String

    -- The spelling box's contents
    , text : String
    , message : Maybe String
    , panel : Maybe Panel

    -- Bumped to restart the shake animation on an invalid guess
    , shakes : Int
    }


defaultSettings : Settings
defaultSettings =
    { accent = "en-GB"
    , length = 5
    , showSpellings = True
    , showCompletions = True
    , showExamples = True
    }


init : D.Value -> ( Model, Cmd Msg )
init flags =
    let
        saved =
            D.decodeValue savedDecoder flags
                |> Result.withDefault
                    { settings = defaultSettings, mode = Daily, puzzleDay = Nothing, daily = Dict.empty, free = Dict.empty }

        model =
            { settings = saved.settings
            , mode = saved.mode
            , today = Nothing
            , puzzleDay = saved.puzzleDay
            , accents = Loading
            , dictionaries = Dict.empty
            , daily = saved.daily
            , free = saved.free
            , row = []
            , text = ""
            , message = Nothing
            , panel = Nothing
            , shakes = 0
            }

        ( loaded, loadCmd ) =
            loadDictionary model
    in
    ( loaded
    , Cmd.batch
        [ loadCmd
        , getToday
        , Http.get { url = "data/accents.json", expect = Http.expectJson GotAccents Dictionary.accentsDecoder }
        ]
    )


getToday : Cmd Msg
getToday =
    Task.perform GotToday (Task.map2 dateString Time.here Time.now)


dateString : Time.Zone -> Time.Posix -> String
dateString zone time =
    let
        pad n =
            String.padLeft 2 '0' (String.fromInt n)

        month =
            case Time.toMonth zone time of
                Time.Jan ->
                    1

                Time.Feb ->
                    2

                Time.Mar ->
                    3

                Time.Apr ->
                    4

                Time.May ->
                    5

                Time.Jun ->
                    6

                Time.Jul ->
                    7

                Time.Aug ->
                    8

                Time.Sep ->
                    9

                Time.Oct ->
                    10

                Time.Nov ->
                    11

                Time.Dec ->
                    12
    in
    String.fromInt (Time.toYear zone time) ++ "-" ++ pad month ++ "-" ++ pad (Time.toDay zone time)


loadDictionary : Model -> ( Model, Cmd Msg )
loadDictionary model =
    let
        tag =
            model.settings.accent
    in
    case Dict.get tag model.dictionaries of
        Just (Loaded _) ->
            ( model, Cmd.none )

        Just Loading ->
            ( model, Cmd.none )

        _ ->
            ( { model | dictionaries = Dict.insert tag Loading model.dictionaries }
            , Http.get
                { url = "data/" ++ tag ++ ".json"
                , expect = Http.expectJson (GotDictionary tag) Dictionary.decoder
                }
            )


currentDictionary : Model -> Maybe Dictionary
currentDictionary model =
    case Dict.get model.settings.accent model.dictionaries of
        Just (Loaded dict) ->
            Just dict

        _ ->
            Nothing


gameKey : Model -> Maybe String
gameKey model =
    let
        base =
            model.settings.accent ++ "/" ++ String.fromInt model.settings.length
    in
    case model.mode of
        Daily ->
            Maybe.map (\day -> base ++ "/" ++ day) model.puzzleDay

        Free ->
            Just base


currentGame : Model -> Maybe Game
currentGame model =
    gameKey model
        |> Maybe.andThen
            (\key ->
                case model.mode of
                    Daily ->
                        Dict.get key model.daily

                    Free ->
                        Dict.get key model.free
            )


{-| Make sure there's a game for the current mode and settings, starting one if
not.
-}
ensureGame : ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
ensureGame ( model, cmd ) =
    case ( currentDictionary model, gameKey model ) of
        ( Just dict, Just key ) ->
            let
                answers =
                    Dictionary.answers dict model.settings.length

                count =
                    Array.length answers
            in
            case model.mode of
                Daily ->
                    if Dict.member key model.daily || count == 0 then
                        ( model, cmd )

                    else
                        case Array.get (Game.dailyIndex key count) answers of
                            Just answer ->
                                ( { model | daily = Dict.insert key { answer = answer, guesses = [] } model.daily }, cmd )

                            Nothing ->
                                ( model, cmd )

                Free ->
                    if Dict.member key model.free || count == 0 then
                        ( model, cmd )

                    else
                        ( model, Cmd.batch [ cmd, Random.generate (NewFreeGame key) (Random.int 0 (count - 1)) ] )

        _ ->
            ( model, cmd )


{-| Move the daily puzzle on to today, unless you're partway through an
earlier one.
-}
catchUp : ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
catchUp ( model, cmd ) =
    let
        inProgress day =
            case Dict.get (model.settings.accent ++ "/" ++ String.fromInt model.settings.length ++ "/" ++ day) model.daily of
                Just game ->
                    game.guesses /= [] && Game.status game == Game.Playing

                Nothing ->
                    False

        puzzleDay =
            if Maybe.map inProgress model.puzzleDay == Just True then
                model.puzzleDay

            else
                model.today
    in
    if puzzleDay == model.puzzleDay then
        ensureGame ( model, cmd )

    else
        ensureGame
            ( if model.mode == Daily then
                clearRow { model | puzzleDay = puzzleDay }

              else
                { model | puzzleDay = puzzleDay }
            , cmd
            )



-- PERSISTENCE


type alias Saved =
    { settings : Settings
    , mode : Mode
    , puzzleDay : Maybe String
    , daily : Dict String Game
    , free : Dict String Game
    }


savedDecoder : D.Decoder Saved
savedDecoder =
    let
        field name dec default =
            D.oneOf [ D.field name dec, D.succeed default ]

        settingsDecoder =
            D.map5 Settings
                (field "accent" D.string defaultSettings.accent)
                (field "length" D.int defaultSettings.length)
                (field "showSpellings" D.bool defaultSettings.showSpellings)
                (field "showCompletions" D.bool defaultSettings.showCompletions)
                (field "showExamples" D.bool defaultSettings.showExamples)

        -- Skip any game that doesn't decode, rather than losing them all.
        gamesDecoder =
            D.keyValuePairs D.value
                |> D.map
                    (List.filterMap
                        (\( key, value ) ->
                            D.decodeValue Game.decoder value
                                |> Result.toMaybe
                                |> Maybe.map (Tuple.pair key)
                        )
                        >> Dict.fromList
                    )

        modeDecoder =
            D.string
                |> D.map
                    (\s ->
                        if s == "free" then
                            Free

                        else
                            Daily
                    )
    in
    D.map5 Saved
        (field "settings" settingsDecoder defaultSettings)
        (field "mode" modeDecoder Daily)
        (field "puzzleDay" (D.nullable D.string) Nothing)
        (field "daily" gamesDecoder Dict.empty)
        (field "free" gamesDecoder Dict.empty)


encodeSaved : Model -> JE.Value
encodeSaved model =
    JE.object
        [ ( "settings"
          , JE.object
                [ ( "accent", JE.string model.settings.accent )
                , ( "length", JE.int model.settings.length )
                , ( "showSpellings", JE.bool model.settings.showSpellings )
                , ( "showCompletions", JE.bool model.settings.showCompletions )
                , ( "showExamples", JE.bool model.settings.showExamples )
                ]
          )
        , ( "mode"
          , JE.string
                (case model.mode of
                    Daily ->
                        "daily"

                    Free ->
                        "free"
                )
          )
        , ( "puzzleDay", Maybe.withDefault JE.null (Maybe.map JE.string model.puzzleDay) )
        , ( "daily", JE.dict identity Game.encode model.daily )
        , ( "free", JE.dict identity Game.encode model.free )
        ]


updateAndSave : Msg -> Model -> ( Model, Cmd Msg )
updateAndSave msg model =
    let
        ( new, cmd ) =
            update msg model

        before =
            JE.encode 0 (encodeSaved model)

        after =
            encodeSaved new
    in
    if JE.encode 0 after == before then
        ( new, cmd )

    else
        ( new, Cmd.batch [ cmd, save after ] )



-- UPDATE


type Msg
    = GotAccents (Result Http.Error (List Dictionary.AccentInfo))
    | GotDictionary String (Result Http.Error Dictionary)
    | GotToday String
    | NewFreeGame String Int
    | PressedPhoneme String
    | PressedBackspace
    | PressedEnter
    | TypedText String
    | Chose String String
    | SetMode Mode
    | StartFreeGame
    | GoToToday
    | SetPanel (Maybe Panel)
    | SetSettings Settings
    | Share
    | Shared String
    | TypedElsewhere String
    | VisibilityChanged Browser.Events.Visibility
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotAccents (Ok accents) ->
            ( { model | accents = Loaded accents }, Cmd.none )

        GotAccents (Err e) ->
            ( { model | accents = Failed (httpError e) }, Cmd.none )

        GotDictionary tag result ->
            ensureGame
                ( { model
                    | dictionaries =
                        Dict.insert tag
                            (case result of
                                Ok dict ->
                                    Loaded dict

                                Err e ->
                                    Failed (httpError e)
                            )
                            model.dictionaries
                  }
                , Cmd.none
                )

        GotToday day ->
            catchUp ( { model | today = Just day }, Cmd.none )

        NewFreeGame key index ->
            case currentDictionary model of
                Just dict ->
                    case Array.get index (Dictionary.answers dict model.settings.length) of
                        Just answer ->
                            ( { model | free = Dict.insert key { answer = answer, guesses = [] } model.free }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        PressedPhoneme id ->
            if playing model && List.length model.row < model.settings.length then
                ( { model | row = model.row ++ [ id ], text = "", message = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        PressedBackspace ->
            if model.text /= "" then
                update (TypedText (String.dropRight 1 model.text)) model

            else
                ( { model | row = List.take (List.length model.row - 1) model.row, message = Nothing }, Cmd.none )

        PressedEnter ->
            submit model

        TypedText text ->
            ( { model
                | text = text
                , message = Nothing
                , row =
                    if not (playing model) then
                        model.row

                    else
                        case Maybe.andThen (\d -> Dictionary.pronunciationsOf d model.settings.length (String.trim text)) (currentDictionary model) of
                            Just ( _, p :: _ ) ->
                                Dictionary.toPhonemes p

                            _ ->
                                []
              }
            , Cmd.none
            )

        Chose key spelling ->
            if playing model then
                ( { model | row = Dictionary.toPhonemes key, text = spelling, message = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        SetMode mode ->
            ensureGame ( clearRow { model | mode = mode }, getToday )

        StartFreeGame ->
            case gameKey { model | mode = Free } of
                Just key ->
                    ensureGame ( clearRow { model | mode = Free, free = Dict.remove key model.free }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        GoToToday ->
            ensureGame ( clearRow { model | puzzleDay = model.today }, Cmd.none )

        SetPanel panel ->
            ( { model | panel = panel }, Cmd.none )

        SetSettings settings ->
            let
                ( loaded, cmd ) =
                    loadDictionary { model | settings = settings }

                rowChanged =
                    settings.accent /= model.settings.accent || settings.length /= model.settings.length
            in
            catchUp
                ( if rowChanged then
                    clearRow loaded

                  else
                    loaded
                , cmd
                )

        Share ->
            case ( currentGame model, currentDictionary model ) of
                ( Just game, Just _ ) ->
                    ( model, share (shareText model game) )

                _ ->
                    ( model, Cmd.none )

        Shared result ->
            ( { model | message = Just result }, Cmd.none )

        TypedElsewhere key ->
            if key == "Enter" then
                submit model

            else if key == "Backspace" then
                update PressedBackspace model

            else if String.length key == 1 && String.all Char.isAlpha key && playing model then
                let
                    ( typed, cmd ) =
                        update (TypedText (model.text ++ key)) model
                in
                ( typed, Cmd.batch [ cmd, Task.attempt (\_ -> NoOp) (Browser.Dom.focus "spelling") ] )

            else
                ( model, Cmd.none )

        VisibilityChanged Browser.Events.Visible ->
            ( model, getToday )

        VisibilityChanged Browser.Events.Hidden ->
            ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


clearRow : Model -> Model
clearRow model =
    { model | row = [], text = "", message = Nothing }


playing : Model -> Bool
playing model =
    Maybe.map Game.status (currentGame model) == Just Game.Playing


submit : Model -> ( Model, Cmd Msg )
submit model =
    case ( currentGame model, currentDictionary model, gameKey model ) of
        ( Just game, Just dict, Just key ) ->
            let
                guess =
                    String.join " " model.row
            in
            if Game.status game /= Game.Playing then
                ( model, Cmd.none )

            else if List.length model.row < model.settings.length then
                ( { model
                    | message =
                        Just
                            (if model.text /= "" then
                                spellingMessage dict model

                             else
                                "Not enough sounds"
                            )
                    , shakes = model.shakes + 1
                  }
                , Cmd.none
                )

            else if Dictionary.entry dict guess == Nothing then
                ( { model | message = Just "That's not a word I know", shakes = model.shakes + 1 }, Cmd.none )

            else
                let
                    updated =
                        { game | guesses = game.guesses ++ [ guess ] }

                    store games =
                        Dict.insert key updated games

                    withGame =
                        case model.mode of
                            Daily ->
                                { model | daily = store model.daily }

                            Free ->
                                { model | free = store model.free }
                in
                ( clearRow withGame, Cmd.none )

        _ ->
            ( model, Cmd.none )


spellingMessage : Dictionary -> Model -> String
spellingMessage dict model =
    case Dictionary.pronunciationsOf dict model.settings.length (String.trim model.text) of
        Just ( word, [] ) ->
            let
                lengths =
                    List.map (Dictionary.toPhonemes >> List.length >> String.fromInt) word.pronunciations
            in
            "“" ++ word.spelling ++ "” has " ++ String.join " or " lengths ++ " sounds, not " ++ String.fromInt model.settings.length

        _ ->
            "I don't know “" ++ String.trim model.text ++ "”"


shareText : Model -> Game -> String
shareText model game =
    let
        result =
            case Game.status game of
                Game.Won ->
                    String.fromInt (List.length game.guesses)

                _ ->
                    "X"

        title =
            case model.mode of
                Daily ->
                    "Sounding " ++ Maybe.withDefault "" model.puzzleDay

                Free ->
                    "Sounding (random)"

        grid =
            game.guesses
                |> List.map
                    (\guess ->
                        Game.score (Dictionary.toPhonemes game.answer) (Dictionary.toPhonemes guess)
                            |> List.map
                                (\mark ->
                                    case mark of
                                        Game.Correct ->
                                            "🟩"

                                        Game.Present ->
                                            "🟨"

                                        Game.Absent ->
                                            "⬜"
                                )
                            |> String.concat
                    )
    in
    String.join "\n"
        ((title ++ " " ++ model.settings.accent ++ " " ++ result ++ "/" ++ String.fromInt Game.maxGuesses) :: grid)


httpError : Http.Error -> String
httpError e =
    case e of
        Http.BadUrl url ->
            "bad URL " ++ url

        Http.Timeout ->
            "timed out"

        Http.NetworkError ->
            "network error"

        Http.BadStatus code ->
            "HTTP " ++ String.fromInt code

        Http.BadBody body ->
            body



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ shared Shared
        , Browser.Events.onVisibilityChange VisibilityChanged
        , Browser.Events.onKeyDown
            (D.map3
                (\key tag modified ->
                    if List.member tag [ "INPUT", "SELECT", "BUTTON", "TEXTAREA" ] then
                        D.fail "focus is elsewhere"

                    else if modified then
                        D.fail "a browser shortcut"

                    else
                        D.succeed (TypedElsewhere key)
                )
                (D.field "key" D.string)
                (D.at [ "target", "tagName" ] D.string)
                (D.map3 (\ctrl meta alt -> ctrl || meta || alt)
                    (D.field "ctrlKey" D.bool)
                    (D.field "metaKey" D.bool)
                    (D.field "altKey" D.bool)
                )
                |> D.andThen identity
            )
        ]



-- VIEW


view : Model -> Html Msg
view model =
    Html.div [ A.class "app" ]
        [ viewHeader model
        , case Dict.get model.settings.accent model.dictionaries of
            Just (Loaded dict) ->
                case currentGame model of
                    Just game ->
                        viewGame model dict game

                    Nothing ->
                        Html.p [ A.class "notice" ] [ Html.text "Setting up…" ]

            Just (Failed e) ->
                Html.p [ A.class "notice" ] [ Html.text ("Couldn't load the dictionary: " ++ e) ]

            _ ->
                Html.p [ A.class "notice" ] [ Html.text "Loading the dictionary…" ]
        , case model.panel of
            Just SettingsPanel ->
                viewSettings model

            Just HelpPanel ->
                viewHelp model

            Nothing ->
                Html.text ""
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    let
        tab mode label =
            Html.button
                [ A.classList [ ( "tab", True ), ( "active", model.mode == mode ) ]
                , E.onClick (SetMode mode)
                , keepFocus
                ]
                [ Html.text label ]
    in
    Html.header []
        [ Html.h1 [] [ Html.text "Sounding" ]
        , Html.nav []
            [ tab Daily ("Daily " ++ Maybe.withDefault "" (Maybe.map (String.dropLeft 5) model.puzzleDay))
            , tab Free "Random"
            ]
        , Html.div [ A.class "header-buttons" ]
            [ Html.button [ A.class "icon", A.title "How to play", E.onClick (SetPanel (Just HelpPanel)), keepFocus ] [ Html.text "?" ]
            , Html.button [ A.class "icon", A.title "Settings", E.onClick (SetPanel (Just SettingsPanel)), keepFocus ] [ Html.text "⚙" ]
            ]
        ]


viewGame : Model -> Dictionary -> Game -> Html Msg
viewGame model dict game =
    let
        answer =
            Dictionary.toPhonemes game.answer

        state =
            Game.status game

        guessRows =
            List.map (viewGuess model dict answer) game.guesses

        currentRow =
            if state == Game.Playing then
                [ viewCurrentRow model dict ]

            else
                []

        emptyRows =
            List.repeat (Game.maxGuesses - List.length guessRows - List.length currentRow) (viewEmptyRow model)
    in
    Html.main_ []
        [ Html.div [ A.class "board", A.attribute "style" ("--length: " ++ String.fromInt model.settings.length) ]
            (guessRows ++ currentRow ++ emptyRows)
        , Html.p [ A.class "message", A.attribute "aria-live" "polite" ]
            [ Html.text (Maybe.withDefault "" model.message) ]
        , if state == Game.Playing then
            Html.div [ A.class "input" ]
                [ viewHelpers model dict
                , viewKeyboard model dict game
                ]

          else
            viewEnd model dict game state
        ]


viewPronunciation : Dictionary -> String -> Html msg
viewPronunciation dict key =
    Html.span [ A.class "ipa" ]
        [ Html.text ("/" ++ String.concat (List.map (Dictionary.label dict) (Dictionary.toPhonemes key)) ++ "/") ]


viewTile : Dictionary -> String -> String -> Html msg
viewTile dict class id =
    Html.div [ A.class ("tile " ++ class) ] [ Html.text (Dictionary.label dict id) ]


markClass : Game.Mark -> String
markClass mark =
    case mark of
        Game.Correct ->
            "correct"

        Game.Present ->
            "present"

        Game.Absent ->
            "absent"


viewGuess : Model -> Dictionary -> List String -> String -> Html Msg
viewGuess model dict answer guess =
    let
        phonemes =
            Dictionary.toPhonemes guess
    in
    Html.div [ A.class "guess" ]
        [ Html.div [ A.class "row" ]
            (List.map2 (\p m -> viewTile dict (markClass m) p) phonemes (Game.score answer phonemes))
        , if model.settings.showSpellings then
            viewSpellings (Dictionary.spellingsOf dict guess)

          else
            Html.text ""
        ]


viewSpellings : List String -> Html msg
viewSpellings spellings =
    let
        shown =
            List.take 4 spellings

        more =
            List.length spellings - List.length shown
    in
    Html.div [ A.class "spellings" ]
        [ Html.text
            (String.join ", " shown
                ++ (if more > 0 then
                        " +" ++ String.fromInt more

                    else
                        ""
                   )
            )
        ]


viewCurrentRow : Model -> Dictionary -> Html Msg
viewCurrentRow model dict =
    let
        filled =
            List.map (viewTile dict "filled") model.row

        blanks =
            List.repeat (model.settings.length - List.length model.row) (Html.div [ A.class "tile" ] [])

        key =
            String.join " " model.row

        preview =
            if model.settings.showSpellings && List.length model.row == model.settings.length then
                viewSpellings (Dictionary.spellingsOf dict key)

            else
                Html.div [ A.class "spellings" ] []
    in
    -- Keyed on the shake count, so that each invalid guess restarts the
    -- shake animation.
    Html.Keyed.node "div"
        [ A.class "guess current" ]
        [ ( String.fromInt model.shakes
          , Html.div
                [ A.classList [ ( "row", True ), ( "shake", model.shakes > 0 ) ] ]
                (filled ++ blanks)
          )
        , ( "spellings", preview )
        ]


viewEmptyRow : Model -> Html Msg
viewEmptyRow model =
    Html.div [ A.class "guess" ]
        [ Html.div [ A.class "row" ] (List.repeat model.settings.length (Html.div [ A.class "tile" ] []))
        , Html.div [ A.class "spellings" ] []
        ]


{-| The spelling box, and suggestions for whatever's being typed.
-}
viewHelpers : Model -> Dictionary -> Html Msg
viewHelpers model dict =
    let
        length =
            model.settings.length

        text =
            String.trim model.text

        suggestions =
            if not model.settings.showCompletions then
                []

            else if text /= "" then
                Dictionary.completeSpelling dict length 6 text
                    |> List.map
                        (\( word, key ) ->
                            Html.button [ A.class "suggestion", E.onClick (Chose key word.spelling), keepFocus ]
                                [ Html.text word.spelling, Html.text " ", viewPronunciation dict key ]
                        )

            else if model.row /= [] && List.length model.row < length then
                let
                    ( entries, total ) =
                        Dictionary.completePronunciation dict length 6 model.row
                in
                List.map
                    (\e ->
                        Html.button [ A.class "suggestion", E.onClick (Chose e.key ""), keepFocus ]
                            [ viewPronunciation dict e.key
                            , Html.text " "
                            , Html.text (String.join ", " (List.take 2 (List.map .spelling e.words)))
                            ]
                    )
                    entries
                    ++ (if total > List.length entries then
                            [ Html.span [ A.class "more" ] [ Html.text ("+" ++ String.fromInt (total - List.length entries) ++ " more") ] ]

                        else if total == 0 then
                            [ Html.span [ A.class "more" ] [ Html.text "No words start like that" ] ]

                        else
                            []
                       )

            else
                []

        lookup =
            case Dictionary.pronunciationsOf dict length text of
                Just ( word, [] ) ->
                    [ Html.span [ A.class "lookup" ]
                        (Html.text (word.spelling ++ ": ")
                            :: List.intersperse (Html.text " or ") (List.map (viewPronunciation dict) word.pronunciations)
                            ++ [ Html.text (" (not " ++ String.fromInt length ++ " sounds)") ]
                        )
                    ]

                _ ->
                    []
    in
    Html.div [ A.class "helpers" ]
        [ Html.div [ A.class "suggestions" ] (lookup ++ suggestions)
        , Html.div [ A.class "entry" ]
            [ Html.button [ A.class "key wide", E.onClick PressedBackspace, A.title "Delete", keepFocus ] [ Html.text "⌫" ]
            , Html.input
                [ A.id "spelling"
                , A.type_ "text"
                , A.value model.text
                , A.placeholder "…or type a word"
                , A.autocomplete False
                , A.spellcheck False
                , A.attribute "autocapitalize" "off"
                , A.attribute "autocorrect" "off"
                , A.attribute "enterkeyhint" "enter"
                , E.onInput TypedText
                , E.on "keydown"
                    (D.field "key" D.string
                        |> D.andThen
                            (\k ->
                                if k == "Enter" then
                                    D.succeed PressedEnter

                                else
                                    D.fail "not enter"
                            )
                    )
                ]
                []
            , Html.button [ A.class "key wide enter", E.onClick PressedEnter, keepFocus ] [ Html.text "Enter" ]
            ]
        ]


{-| Stop game buttons taking focus when clicked, so that a physical Enter
afterwards submits the guess rather than pressing the same button again, and
so that the spelling box keeps focus while you use them.
-}
keepFocus : Html.Attribute Msg
keepFocus =
    E.preventDefaultOn "mousedown" (D.succeed ( NoOp, True ))


viewKeyboard : Model -> Dictionary -> Game -> Html Msg
viewKeyboard model dict game =
    let
        marks =
            Game.keyMarks Dictionary.toPhonemes game

        phonemes =
            Dict.fromList (List.map (\p -> ( p.id, p )) dict.accent.phonemes)

        viewKey id =
            let
                ( before, highlighted, after ) =
                    Dict.get id phonemes |> Maybe.map .example |> Maybe.withDefault ( "", "", "" )

                markClasses =
                    case Dict.get id marks of
                        Just mark ->
                            " " ++ markClass mark

                        Nothing ->
                            ""
            in
            Html.button
                [ A.class ("key" ++ markClasses)
                , E.onClick (PressedPhoneme id)
                , keepFocus
                , A.title (before ++ highlighted ++ after)
                ]
                [ Html.span [ A.class "label" ] [ Html.text (Dictionary.label dict id) ]
                , if model.settings.showExamples then
                    Html.span [ A.class "example" ]
                        [ Html.text before, Html.b [] [ Html.text highlighted ], Html.text after ]

                  else
                    Html.text ""
                ]
    in
    Html.div [ A.classList [ ( "keyboard", True ), ( "with-examples", model.settings.showExamples ) ] ]
        (List.map (\row -> Html.div [ A.class "keyrow" ] (List.map viewKey row)) dict.accent.keyboard)


viewEnd : Model -> Dictionary -> Game -> Game.Status -> Html Msg
viewEnd model dict game state =
    let
        words =
            Dictionary.entry dict game.answer |> Maybe.map .words |> Maybe.withDefault []
    in
    Html.div [ A.class "end" ]
        [ Html.p [ A.class "verdict" ]
            [ Html.text
                (if state == Game.Won then
                    "Got it in " ++ String.fromInt (List.length game.guesses) ++ "!"

                 else
                    "Out of guesses. The answer was"
                )
            ]
        , Html.p [ A.class "answer" ]
            [ viewPronunciation dict game.answer
            , Html.text " "
            , Html.text (String.join ", " (List.map .spelling words))
            ]
        , Html.div [ A.class "end-buttons" ]
            ([ Html.button [ E.onClick Share ] [ Html.text "Share" ] ]
                ++ (if model.mode == Daily && model.puzzleDay /= model.today then
                        [ Html.button [ E.onClick GoToToday ] [ Html.text "Today's puzzle" ] ]

                    else
                        []
                   )
                ++ [ Html.button [ E.onClick StartFreeGame ] [ Html.text "New random game" ] ]
            )
        ]


viewOverlay : String -> List (Html Msg) -> Html Msg
viewOverlay title content =
    Html.div [ A.class "overlay", E.onClick (SetPanel Nothing) ]
        [ Html.div [ A.class "panel", E.stopPropagationOn "click" (D.succeed ( NoOp, True )) ]
            (Html.div [ A.class "panel-header" ]
                [ Html.h2 [] [ Html.text title ]
                , Html.button [ A.class "icon", E.onClick (SetPanel Nothing), A.title "Close" ] [ Html.text "✕" ]
                ]
                :: content
            )
        ]


viewSettings : Model -> Html Msg
viewSettings model =
    let
        s =
            model.settings

        checkbox label checked set =
            Html.label [ A.class "setting" ]
                [ Html.input [ A.type_ "checkbox", A.checked checked, E.onCheck set ] []
                , Html.text label
                ]

        accents =
            case model.accents of
                Loaded list ->
                    list

                _ ->
                    [ { tag = s.accent, name = s.accent } ]
    in
    viewOverlay "Settings"
        [ Html.label [ A.class "setting" ]
            [ Html.text "Accent "
            , Html.select [ E.onInput (\tag -> SetSettings { s | accent = tag }) ]
                (List.map
                    (\a -> Html.option [ A.value a.tag, A.selected (a.tag == s.accent) ] [ Html.text a.name ])
                    accents
                )
            ]
        , Html.div [ A.class "setting" ]
            (Html.text "Sounds per word "
                :: List.map
                    (\n ->
                        Html.button
                            [ A.classList [ ( "choice", True ), ( "active", s.length == n ) ]
                            , E.onClick (SetSettings { s | length = n })
                            ]
                            [ Html.text (String.fromInt n) ]
                    )
                    [ 4, 5, 6 ]
            )
        , checkbox "Show spellings of guesses" s.showSpellings (\b -> SetSettings { s | showSpellings = b })
        , checkbox "Suggest words as I type" s.showCompletions (\b -> SetSettings { s | showCompletions = b })
        , checkbox "Show example words on keys" s.showExamples (\b -> SetSettings { s | showExamples = b })
        , Html.p [ A.class "small" ]
            [ Html.text "Daily and random games are kept separately, so you can switch between them at any time." ]
        ]


viewHelp : Model -> Html Msg
viewHelp model =
    viewOverlay "How to play"
        [ Html.p []
            [ Html.text "Guess the word in six tries, like Wordle, but by its "
            , Html.em [] [ Html.text "sounds" ]
            , Html.text " rather than its letters. Each tile is one phoneme: “bath” is "
            , Html.span [ A.class "ipa" ] [ Html.text "/b ɑː θ/" ]
            , Html.text ", three sounds."
            ]
        , Html.p []
            [ Html.span [ A.class "tile mini correct" ] [ Html.text "ɑː" ]
            , Html.text " right sound, right place. "
            , Html.span [ A.class "tile mini present" ] [ Html.text "θ" ]
            , Html.text " in the word, elsewhere. "
            , Html.span [ A.class "tile mini absent" ] [ Html.text "b" ]
            , Html.text " not in the word (or not that many times)."
            ]
        , Html.p []
            [ Html.text "Enter sounds with the keyboard, whose keys show an example word with the sound in bold, or type an ordinary word in the box and its pronunciation will fill the row." ]
        , Html.p []
            [ Html.text "Homophones are the same guess: what counts is the sounds. Pronunciations are for "
            , Html.text
                (case Dict.get model.settings.accent model.dictionaries of
                    Just (Loaded dict) ->
                        dict.accent.name

                    _ ->
                        model.settings.accent
                )
            , Html.text "."
            ]
        , Html.h3 [] [ Html.text "Sources" ]
        , Html.ul [ A.class "small" ]
            [ Html.li [] [ Html.a [ A.href "https://github.com/JoseLlarena/Britfone" ] [ Html.text "Britfone" ], Html.text " (MIT licence)" ]
            , Html.li [] [ Html.a [ A.href "https://en.wiktionary.org/" ] [ Html.text "Wiktionary" ], Html.text " via ", Html.a [ A.href "https://kaikki.org/" ] [ Html.text "kaikki.org" ], Html.text " (CC BY-SA 4.0)" ]
            , Html.li [] [ Html.a [ A.href "https://github.com/espeak-ng/espeak-ng" ] [ Html.text "eSpeak NG" ], Html.text " for words the others don't have" ]
            , Html.li [] [ Html.a [ A.href "https://github.com/rspeer/wordfreq" ] [ Html.text "wordfreq" ], Html.text " for word frequencies (CC BY-SA 4.0)" ]
            ]
        , Html.p [ A.class "small" ]
            [ Html.text "Inspired by "
            , Html.a [ A.href "https://joshuamandel.com/heardle/" ] [ Html.text "Heardle" ]
            , Html.text " by Carrie Niziolek and Josh Mandel."
            ]
        ]
