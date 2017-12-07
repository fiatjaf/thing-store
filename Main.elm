import Html exposing
  ( Html, text , div
  , button
  )
import Html.Lazy exposing (..)
import Html.Attributes exposing (class)
import Html.Events exposing (onMouseDown)
import Dict exposing (Dict, insert, get)
import Array exposing (Array)
import Platform.Sub as Sub
import Mouse exposing (Position)
import ContextMenu exposing (ContextMenu)

import Record exposing (..)
import Helpers exposing (..)
import Menu exposing (..)
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
  , blank : String
  }


-- MODEL


type alias Model =
  { records : Records
  , blank_id : String
  , next_blank_id : String
  , dragging : Maybe ( String, Position )
  , pending_saves : Int
  , context_menu : ContextMenu Context
  }


init : Flags -> (Model, Cmd Msg)
init flags =
  let
    (context_menu, msg) = ContextMenu.init
  in
    ( Model
      ( ( Dict.fromList
          <| List.map (\r -> ( r.id, r )) flags.records
        )
        |> add flags.blank
      ) 
      flags.blank
      ""
      Nothing
      0
      context_menu
    , Cmd.batch
      [ requestId ()
      , Cmd.map ContextMenuAction msg
      ]
    )


-- UPDATE


type Msg
  = NextBlankId String
  | PendingSaves Int
  | UnfocusAll
  | RecordAction String Record.Msg
  | ContextMenuAction (ContextMenu.Msg Context)
  | Noop

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    NextBlankId id -> ( { model | next_blank_id = id }, Cmd.none )
    PendingSaves n -> ( { model | pending_saves = n }, Cmd.none )
    UnfocusAll -> 
      ( { model | records = model.records |> Dict.map (\_ r -> { r | focused = False }) }
      , Cmd.none
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
                if id == model.blank_id
                then
                  ( { model
                      | records = model.records |> add model.next_blank_id
                      , blank_id = model.next_blank_id
                    }
                  , Cmd.batch
                    [ queueRecord r
                    , requestId ()
                    ]
                  )
                else
                  ( model
                  , queueRecord r
                  )
              ChangeValue idx k v ->
                if id == model.blank_id
                then
                  ( { model
                      | records = model.records |> add model.next_blank_id
                      , blank_id = model.next_blank_id
                    }
                  , Cmd.batch
                    [ changedValue (id, idx, k, v)
                    , queueRecord r
                    , requestId ()
                    ]
                  )
                else
                  ( model
                  , Cmd.batch
                    [ changedValue (id, idx, k, v)
                    , queueRecord r
                    ]
                  )
              DeleteRow idx ->
                ( model
                , Cmd.batch
                  [ changedValue (id, idx, r.k |> Array.get idx |> Maybe.withDefault "", "")
                  , queueRecord r
                  ]
                )
              RecordContextMenuAction msg -> update (ContextMenuAction msg) model
              _ -> ( model, Cmd.none )
          in 
            ( { m | records = m.records |> insert id r }
            , Cmd.batch [ mcmd, Cmd.map (RecordAction id) rcmd ]
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
    , Sub.map ContextMenuAction (ContextMenu.subscriptions model.context_menu)
    ]


-- VIEW


view : Model -> Html Msg
view model =
  div []
    [ div [ class "context-menu" ]
      [ ContextMenu.view
        Menu.config
        ContextMenuAction
        viewContextMenuItems
        model.context_menu
      ]
    , div [ class "columns is-mobile" ]
      [ div [ class "column" ] [ text "data at \"~\"" ]
      , div [ class "column" ]
        [ button [ class "button" ]
          [ text <| "save " ++ (toString model.pending_saves) ++ " modified records"
          ]
        ]
      ]
    , div
        [ class "record-container"
        , onMouseDown UnfocusAll
        ]
      <| List.map (\(id, r) -> Html.map (RecordAction id) (lazy Record.view r))
      <| Dict.toList model.records
    ]


viewContextMenuItems : Context -> List (List ( ContextMenu.Item, Msg ))
viewContextMenuItems context =
  case context of
    BackgroundContext -> []
    RecordContext id -> []
    KeyValueContext id idx ->
      [ [ ( ContextMenu.item "Delete row", RecordAction id (DeleteRow idx) ) ]
      ]
