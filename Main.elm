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
import Toolkit.Maybe as M
import Color
import Mouse exposing (Position)
import ContextMenu exposing (ContextMenu, item)

import Record exposing (..)
import Helpers exposing (..)
import Settings exposing (..)
import Ports exposing (..)


main =
  Html.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

-- MODEL


type alias Model =
  { records : Dict String Record
  , next_id : String
  , pending_saves : Int
  , page : Page
  , view : View
  , settings : Settings
  , notification : Maybe String
  , dragging : Maybe ( String, Position )
  , resizing : Maybe ( String, Int )
  , context_menu : ContextMenu MenuContext
  , editing_linked : Maybe (String, Int)
  }

type Page
  = HomePage
  | SettingsPage

type View
  = FloatingView
  | TableView
  | JSONView String

init : (Model, Cmd Msg)
init =
  let
    (context_menu, msg) = ContextMenu.init
  in
    ( { records = Dict.empty
      , pending_saves = 0
      , view = FloatingView
      , page = HomePage
      , settings = defaultSettings
      , next_id = ""
      , notification = Nothing
      , dragging = Nothing
      , resizing  = Nothing
      , context_menu = context_menu
      , editing_linked = Nothing
      }
    , Cmd.batch
      [ requestId ()
      , Cmd.map ContextMenuAction msg
      ]
    )

menuConfig =
  { width = 200
  , direction = ContextMenu.RightBottom
  , overflowX = ContextMenu.Mirror
  , overflowY = ContextMenu.Mirror
  , containerColor = Color.white
  , hoverColor = Color.rgb 240 240 240
  , invertText = False
  , cursor = ContextMenu.Pointer
  , rounded = False
  , fontFamily = "inherit"
  }


-- UPDATE


type Msg
  = EraseNotification
  | Notify String
  | Navigate Page
  | GotUpdatedConfig Config
  | GotUpdatedRecord RestrictedRecord
  | GotDeletedRecord String
  | NextBlankId String
  | PendingSaves Int
  | SavePending
  | ReplaceRecords (List Record)
  | TypeView String
  | SaveView
  | UnfocusAll
  | ChangeView View
  | NewRecord (Maybe (Int, Array String))
  | CopyRecord String
  | DeleteRecord String
  | StopEditingLinked
  | RecordAction String Record.Msg
  | SettingsAction Settings.Msg
  | ContextMenuAction (ContextMenu.Msg MenuContext)
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
    GotUpdatedConfig c ->
      let settings = model.settings
      in ( { model | settings = { settings | config = c } }, Cmd.none )
    GotUpdatedRecord rr ->
      ( { model | records = model.records |> insert rr.id ( fromRestricted rr ) }
      , Cmd.none
      )
    GotDeletedRecord id ->
      ( { model | records = model.records |> Dict.remove id }
      , Cmd.none
      )
    NextBlankId id -> ( { model | next_id = id }, Cmd.none )
    PendingSaves n -> ( { model | pending_saves = n }, Cmd.none )
    SavePending -> ( model, saveToPouch () )
    ReplaceRecords recordlist ->
      ( { model | records = Dict.fromList <| List.map (\r -> (r.id, r)) recordlist }
      , Cmd.none
      )
    TypeView t ->
      ( { model | view = JSONView t }
      , runView t
      )
    SaveView -> ( model, Cmd.none )
    UnfocusAll -> 
      ( { model | records = model.records |> Dict.map (\_ r -> { r | focused = False }) }
      , Cmd.none
      )
    ChangeView v -> ( { model | view = v, dragging = Nothing }, Cmd.none )
    NewRecord (Just (index, default_fields)) ->
      ( { model | records = model.records
          |> add model.next_id (Just index) (Just default_fields) }
      , requestId ()
      )
    NewRecord Nothing -> update (NewRecord Nothing) model
    CopyRecord id ->
      case model.records |> get id of
        Nothing -> ( model, Cmd.none )
        Just base ->
          ( { model | records = model.records |> add model.next_id base.kind (Just base.k) }
          , requestId ()
          )
    DeleteRecord id ->
      ( { model | records = model.records |> Dict.remove id }
      , queueDeleteRecord id
      )
    StopEditingLinked -> ( { model | editing_linked = Debug.log "stopping" Nothing }, Cmd.none )
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
              ResizeStart x -> ( { model | resizing = Just (id, x) }, Cmd.none )
              ResizeEnd x ->
                ( { model | resizing = Nothing }
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
              ChangeKind k ->
                ( model
                , Cmd.batch
                  [ queueRecord r
                  , changedKind (id, oldr.kind, k)
                  ]
                )
              EditLinked to_edit ->
                ( { model | editing_linked = Debug.log "editing" Just to_edit }
                , Cmd.none
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
    SettingsAction smsg ->
      let
        (s, scmd) = Settings.update smsg model.settings
        (m, mcmd) = case smsg of 
          KindAction i SaveKind -> ( model, saveConfig s.config )
          KindAction _ _ -> ( model, changedConfig s.config )
          _ -> ( model, Cmd.none )
      in
        ( { m | settings = s }
        , Cmd.batch
            [ Cmd.map SettingsAction scmd
            , mcmd
            ]
        )
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
    [ gotUpdatedConfig GotUpdatedConfig
    , gotUpdatedRecord GotUpdatedRecord
    , gotDeletedRecord GotDeletedRecord
    , gotId NextBlankId
    , case model.dragging of
      Nothing ->
        case model.resizing of
          Nothing -> Sub.none
          Just (id, initial) ->
            Sub.batch
              [ Mouse.moves (\{x, y} -> RecordAction id <| ResizeAt (x - initial))
              , Mouse.ups (\{x, y} -> (RecordAction id <| ResizeEnd x))
              ]
      Just (id, base) ->
        Sub.batch
          [ Mouse.moves
            (\p -> RecordAction id <| DragAt { x = p.x - base.x, y = p.y - base.y })
          , Mouse.ups (RecordAction id << DragEnd)
          ]
    , gotPendingSaves PendingSaves
    , gotCalcResult (\(id,idx,v) -> RecordAction id (CalcResult idx v))
    , gotCalcError (\(id,idx,v) -> RecordAction id (CalcError idx v))
    , replaceRecords (List.map fromRestricted >> ReplaceRecords)
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
        menuConfig
        ContextMenuAction
        ( viewContextMenuItems model.settings.config.kinds )
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
              ] []
            ]
          , button [ class "button", onClick SaveView ] [ text "Save view" ]
          ]
        ]
      , div [ class "column is-narrow" ]
        [ div [ class "dropdown is-hoverable" ]
          [ button [ class "button", onClick (NewRecord Nothing) ] [ text "New" ]
          , div [ class "dropdown-menu" ]
            [ div [ class "dropdown-content" ]
              <| List.indexedMap
                (\index kind ->
                  a
                    [ class "dropdown-item"
                    , onClick (NewRecord (Just (index, kind.default_fields)))
                    ] [ text <| "New '" ++ kind.name ++ "'" ]
                )
              <| Array.toList model.settings.config.kinds
            ]
          ]
        ]
      , div [ class "column is-narrow" ] <|
        case model.view of
          TableView -> 
            [ button
              [ class "button"
              , onClick <| ChangeView FloatingView
              ] [ text "View records" ]
            ]
          FloatingView ->
            [ button
              [ class "button"
              , onClick <| ChangeView TableView
              ] [ text "View table" ]
            ]
          JSONView jq -> []
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
      [ let kinds = model.settings.config.kinds
            kind = grabKind kinds
        in case model.view of
        FloatingView -> 
          div [ class "floating-view" ]
            <| List.map
              (\(id, r) -> Html.map (RecordAction id) (lazy2 viewFloating (kind r) r))
            <| Dict.toList model.records
        TableView ->
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
                  (\(id, r) -> Html.map (RecordAction id) (lazy3 viewRow (kind r) keys r))
                <| Dict.toList model.records
              ]
        JSONView jq -> div [] []
      ]
    , case model.editing_linked of
      Nothing -> text ""
      Just (id, idx) ->
        case Dict.get id model.records of
          Nothing -> text ""
          Just rec ->
            case M.zip3 ( Array.get idx rec.k, Array.get idx rec.v, Array.get idx rec.c ) of
              Nothing -> text ""
              Just kvc ->
                div
                  [ class "foreground-field"
                  , onClick StopEditingLinked
                  ]
                  [ Html.map (RecordAction rec.id)
                    <| viewLinkedValue model.records rec idx kvc
                  ]
    ]

viewContextMenuItems : Array Kind -> MenuContext -> List (List ( ContextMenu.Item, Msg ))
viewContextMenuItems kinds context =
  case context of
    BackgroundContext -> []
    RecordContext rec ->
      [ kinds
        |> Array.toList
        |> List.indexedMap
          (\index kind ->
            ( item ("Change kind to " ++ kind.name)
            , RecordAction rec.id (ChangeKind <| Just index)
            )
          )
        |> (::) ( item "Remove kind", RecordAction rec.id (ChangeKind Nothing))
      , [ ( item "Copy record template", CopyRecord rec.id )
        ]
      , [ ( item "Delete record", DeleteRecord rec.id )
        ]
      ]
    KeyValueContext rec idx ->
      [ [ ( item "Delete row", RecordAction rec.id (DeleteRow idx) )
        ]
      , [ case rec.f |> Array.get idx of
            Nothing -> ( item "", Noop )
            Just field ->
              if field.linked
              then
                ( item "Turn into normal"
                , RecordAction rec.id (ChangeLinked False idx)
                )
              else
                ( item "Turn into linked"
                , RecordAction rec.id (ChangeLinked True idx)
                )
        ]
      ]
