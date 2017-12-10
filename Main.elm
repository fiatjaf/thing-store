import Html exposing
  ( Html, text, div, header, nav
  , table, tr, th, tbody, thead
  , button, input, a
  )
import Html.Lazy exposing (..)
import Html.Attributes exposing (class, value)
import Html.Events exposing (onMouseDown, onClick, onInput)
import Dict exposing (Dict, insert, get)
import Array exposing (Array)
import Set exposing (Set)
import Platform.Sub as Sub
import Mouse exposing (Position)
import ContextMenu exposing (ContextMenu)

import Record exposing (..)
import Helpers exposing (..)
import Menu exposing (..)
import Settings exposing (..)
import Ports exposing (..)


main =
  Html.programWithFlags
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

type alias Flags =
  { records : List Record
  , config : Settings
  , blank : String
  }


-- MODEL


type alias Model =
  { records : Dict String Record
  , next_id : String
  , format : Format
  , view : View
  , settings : Settings
  , notification : Maybe String
  , dragging : Maybe ( String, Position )
  , pending_saves : Int
  , context_menu : ContextMenu Context
  , page : Page
  }

type Page
  = HomePage
  | SettingsPage

type Format
  = Floating
  | Table

type View
  = SavedView String String
  | TypingView String


init : Flags -> (Model, Cmd Msg)
init flags =
  let
    (context_menu, msg) = ContextMenu.init
    records = Dict.fromList <| List.map (\r -> ( r.id, r )) flags.records
    nrecords = Dict.size records
  in
    ( Model
      ( records |> if nrecords == 0 then add flags.blank else identity )
      ""
      Floating
      ( TypingView "" )
      flags.config
      Nothing
      Nothing
      0
      context_menu
      HomePage
    , Cmd.batch
      [ requestId ()
      , Cmd.map ContextMenuAction msg
      , Cmd.batch <| 
        ( List.concat
          <| List.map
            (\r -> Array.toList
              <| Array.indexedMap (\idx v -> changedValue (r.id, idx, v))
              <| r.v
            )
          <| flags.records
        )
      ]
    )


-- UPDATE


type Msg
  = EraseNotification
  | Notify String
  | Navigate Page
  | NextBlankId String
  | PendingSaves Int
  | SavePending
  | ReplaceRecords (List Record)
  | TypeView String
  | SaveView
  | UnfocusAll
  | ChangeFormat Format
  | NewRecord
  | CopyRecord String
  | RecordAction String Record.Msg
  | SettingsAction Settings.Msg
  | ContextMenuAction (ContextMenu.Msg Context)
  | Noop

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    EraseNotification ->
      ( { model | notification = Nothing }
      , Cmd.none
      )
    Notify text ->
      ( { model | notification = Just text }
      , delay 5 EraseNotification
      )
    Navigate page -> ( { model | page = page }, Cmd.none )
    NextBlankId id -> ( { model | next_id = id }, Cmd.none )
    PendingSaves n -> ( { model | pending_saves = n }, Cmd.none )
    SavePending -> ( model, saveToPouch () )
    ReplaceRecords recordlist ->
      ( { model | records = Dict.fromList <| List.map (\r -> (r.id, r)) recordlist }
      , Cmd.none
      )
    TypeView t ->
      ( { model | view = TypingView t }
      , runView t
      )
    SaveView -> ( model, Cmd.none )
    UnfocusAll -> 
      ( { model | records = model.records |> Dict.map (\_ r -> { r | focused = False }) }
      , Cmd.none
      )
    ChangeFormat v -> ( { model | format = v, dragging = Nothing }, Cmd.none )
    NewRecord ->
      ( { model | records = model.records |> add model.next_id }
      , requestId ()
      )
    CopyRecord id ->
      case model.records |> get id |> Maybe.map (fromTemplate model.next_id) of
        Nothing -> ( model, Cmd.none )
        Just copy ->
          ( { model | records = model.records |> insert model.next_id copy }
          , requestId ()
          )
    RecordAction id rmsg ->
      case get id model.records of
        Nothing -> ( model, Cmd.none )
        Just oldr ->
          let
            (r, rcmd) = Record.update rmsg oldr
            (m, mcmd) = case rmsg of 
              DragStart pos -> ( { model | dragging = Just (id, pos) }, Cmd.none )
              DragEnd pos ->
                ( { model | dragging = Nothing }
                , queueRecord r
                )
              Focus -> if r.focused then ( model, Cmd.none ) else update UnfocusAll model
              ChangeKey _ _ ->
                ( model
                , queueRecord r
                )
              ChangeValue idx v ->
                ( model
                , Cmd.batch
                  [ changedValue (id, idx, v)
                  , queueRecord r
                  ]
                )
              DeleteRow idx ->
                ( model
                , Cmd.batch
                  [ changedValue (id, idx, "")
                  , queueRecord r
                  ]
                )
              RecordContextMenuAction msg -> update (ContextMenuAction msg) model
              _ -> ( model, Cmd.none )
          in 
            ( { m | records = m.records |> insert id r }
            , Cmd.batch [ mcmd, Cmd.map (RecordAction id) rcmd ]
            )
    SettingsAction msg -> ( model, Cmd.none )
    ContextMenuAction msg ->
      let
        (context_menu, cmd) = ContextMenu.update msg model.context_menu
      in
        ( { model | context_menu = context_menu }
        , Cmd.map ContextMenuAction cmd
        )
    Noop -> ( model, Cmd.none )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ gotId NextBlankId
    , case model.dragging of
      Nothing -> Sub.none
      Just (id, base) ->
        Sub.batch
          [ Mouse.moves
            (\p -> RecordAction id <| DragAt { x = p.x - base.x, y = p.y - base.y })
          , Mouse.ups (RecordAction id << DragEnd)
          ]
    , gotPendingSaves PendingSaves
    , gotCalcResult (\(id,idx,v) -> RecordAction id (CalcResult idx v))
    , gotCalcError (\(id,idx,v) -> RecordAction id (CalcError idx v))
    , replaceRecords ReplaceRecords
    , Sub.map ContextMenuAction (ContextMenu.subscriptions model.context_menu)
    , notify Notify
    ]


-- VIEW


view : Model -> Html Msg
view model =
  div []
    [ nav [ class "navbar" ]
      [ div [ class "navbar-brand" ]
        [ div [ class "navbar-item" ] [ text "data at \"~\"" ]
        , div [ class "navbar-burger" ] []
        ]
      , div [ class "navbar-menu" ]
        [ div [ class "navbar-start" ] []
        , div [ class "navbar-end" ]
          [ a
            [ class "navbar-item"
            , onClick <| Navigate SettingsPage
            ] [ text "menu" ]
          , a
            [ class "navbar-item"
            , onClick <| Navigate HomePage
            ] [ text "records" ]
          ]
        ]
      ]
    , model.notification
      |> Maybe.map (div [ class "notification" ] << List.singleton << text)
      |> Maybe.withDefault (text "")
    , div [ class "context-menu" ]
      [ ContextMenu.view
        Menu.config
        ContextMenuAction
        viewContextMenuItems
        model.context_menu
      ]
    , case model.page of
      HomePage -> viewHome model
      SettingsPage -> Html.map SettingsAction (Settings.view model.settings)
    ]

viewHome : Model -> Html Msg
viewHome model =
  div []
    [ header [ class "columns is-mobile" ]
      [ div [ class "column" ]
        [ div [ class "field is-grouped" ]
          [ div [ class "control is-expanded" ]
            [ input
              [ class "input"
              , onInput TypeView
              , value <| case model.view of
                TypingView t -> t
                SavedView _ t -> t
              ] []
            ]
          , button [ class "button", onClick SaveView ] [ text "Save view" ]
          ]
        ]
      , div [ class "column is-narrow" ]
        [ button [ class "button", onClick NewRecord ] [ text "New" ]
        ]
      , div [ class "column is-narrow" ] <|
        case model.format of
          Table -> 
            [ button
              [ class "button"
              , onClick <| ChangeFormat Floating
              ] [ text "View records" ]
            ]
          Floating ->
            [ button
              [ class "button"
              , onClick <| ChangeFormat Table
              ] [ text "View table" ]
            ]
      , div [ class "column is-narrow" ]
        [ button
          [ class "button"
          , onClick SavePending
          ] [ text <| "Save " ++ (toString model.pending_saves) ++ " modified records"
          ]
        ]
      ]
    , div
      [ class "record-container"
      , onMouseDown UnfocusAll
      ]
      [ case model.format of
        Floating -> 
          div [ class "floating-view" ]
            <| List.map (\(id, r) -> Html.map (RecordAction id) (lazy Record.viewFloating r))
            <| Dict.toList model.records
        Table ->
          let
            keys = model.records
              |> Dict.values
              |> List.foldl
                (\rec acc ->
                  Set.union acc (Set.remove "" <| Set.fromList <| Array.toList rec.k)
                ) Set.empty
              |> Set.toList
          in
            table [ class "table is-bordered table-view" ]
              [ thead []
                [ tr []
                  <| (::) (th [] [ text "id" ])
                  <| List.map (th [] << List.singleton << text) keys
                ]
              , tbody []
                <| List.map
                  (\(id, r) -> Html.map (RecordAction id) (lazy2 viewRow keys r))
                <| Dict.toList model.records
              ]
      ]
    ]

viewContextMenuItems : Context -> List (List ( ContextMenu.Item, Msg ))
viewContextMenuItems context =
  case context of
    BackgroundContext -> []
    RecordContext id ->
      [ [ ( ContextMenu.item "Copy record template", CopyRecord id )
        ]
      ]
    KeyValueContext id idx ->
      [ [ ( ContextMenu.item "Delete row", RecordAction id (DeleteRow idx) )
        ]
      ]
