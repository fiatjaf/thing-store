import Html exposing
  ( Html, text , div
  )
import Html.Lazy exposing (..)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick, onInput)
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
  , dragging : Maybe String
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
  , Cmd.batch
    [ requestId ()
    ]
  )


-- UPDATE


type Msg
  = NextBlankId String
  | RecordAction String RecordMsg
  | Noop

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    NextBlankId id -> ( { model | next_blank_id = id }, Cmd.none )
    RecordAction id rmsg ->
      case get id model.records of
        Nothing -> ( model, Cmd.none )
        Just oldr ->
          let
            (r, rcmd) = Record.update rmsg oldr
            (m, mcmd) = case rmsg of 
              DragStart -> ( { model | dragging = Just id }, Cmd.none )
              DragEnd pos ->
                ( { model | dragging = Nothing }
                , queueRecord r
                )
              _ -> ( model, Cmd.none )
          in 
            ( { m | records = model.records |> insert id r }
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
      Just id ->
        Sub.batch
          [ Mouse.moves (RecordAction id << DragAt)
          , Mouse.ups (RecordAction id << DragEnd)
          ]
    ]


-- VIEW


view : Model -> Html Msg
view model =
  div []
    [ text "data at \"~\""
    , div []
      [ text <| "next id: " ++ model.next_blank_id
      ]
    , div [ class "record-container" ]
      <| List.map (\(id, r) -> Html.map (RecordAction id) (lazy Record.view r))
      <| Dict.toList model.records
    ]
