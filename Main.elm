import Html exposing
  ( Html, text , div
  , button
  )
import Html.Lazy exposing (..)
import Html.Attributes exposing (class)
import Html.Events exposing (onMouseDown)
import Dict exposing (Dict, insert, get)
import Platform.Sub as Sub
import Json.Decode as J
import Mouse exposing (Position)

import Record exposing (..)
import Helpers exposing (..)
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
  }


init : Flags -> (Model, Cmd Msg)
init flags =
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
  , Cmd.batch
    [ requestId ()
    ]
  )


-- UPDATE


type Msg
  = NextBlankId String
  | PendingSaves Int
  | UnfocusAll
  | RecordAction String RecordMsg
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
              ChangeValue idx v ->
                if id == model.blank_id
                then
                  ( { model
                      | records = model.records |> add model.next_blank_id
                      , blank_id = model.next_blank_id
                    }
                  , Cmd.batch
                    [ queueRecord r
                    , calc (id, idx, v)
                    , requestId ()
                    ]
                  )
                else
                  ( model
                  , Cmd.batch
                    [ calc (id, idx, v)
                    , queueRecord r
                    ]
                  )
              _ -> ( model, Cmd.none )
          in 
            ( { m | records = m.records |> insert id r }
            , Cmd.batch [ mcmd, Cmd.map (RecordAction id) rcmd ]
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
    ]


-- VIEW


view : Model -> Html Msg
view model =
  div []
    [ text "data at \"~\""
    , div [ class "columns is-mobile" ]
      [ div [ class "column" ] [ text <| "next id: " ++ model.next_blank_id ]
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
