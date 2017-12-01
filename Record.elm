module Record exposing (..)

import Html exposing
  ( Html, text , div
  , table, tr, td, th
  , input
  )
import Html.Attributes exposing (class, style)
import Html.Events exposing (onMouseDown)
import Dict exposing (Dict, insert, get)
import Json.Decode as Decode
import Mouse exposing (Position)

import Helpers exposing (..)


-- MODEL


type alias Record =
  { id : String
  , kv : List ( String, String )
  , calc : List String
  , pos : Position
  }

type alias Records = Dict String Record

add : String -> Records -> Records
add id records =
  let
    rec = Record
      id
      [ ("", "") ]
      [ "" ]
      { x = 200, y = 200 }
  in
    insert id rec records


-- UPDATE


type RecordMsg
  = DragStart
  | DragAt Position
  | DragEnd Position


update : RecordMsg -> Record -> (Record, Cmd RecordMsg)
update msg record =
  case msg of
    DragStart -> ( record, Cmd.none )
    DragAt pos -> ( { record | pos = Debug.log "pos" pos }, Cmd.none )
    DragEnd pos -> ( record, Cmd.none )


-- VIEW


view : Record -> Html RecordMsg
view rec =
  div
    [ class "record"
    , onMouseDown DragStart
    , style
      [ "position" => "absolute"
      , "left" => px rec.pos.x
      , "top" => px rec.pos.y
      ]
    ]
    [ table [] <|
      List.map viewKV rec.kv
    ]

viewKV : ( String, String ) -> Html RecordMsg
viewKV (k, v) =
  tr []
    [ th [] [ text k ]
    , td [] [ text v ]
    ]
