module Record exposing (..)

import Html exposing
  ( Html, text , div
  , table, tr, td, th
  , input
  )
import Html.Attributes exposing (class, style, value, readonly, title)
import Html.Events exposing (on, onMouseUp, onInput)
import Dict exposing (Dict, insert, get)
import Json.Decode as Decode
import Array exposing (Array)
import Mouse exposing (Position)

import Helpers exposing (..)


-- MODEL


type alias Record =
  { id : String
  , k : Array String
  , v : Array String
  , calc : Array String
  , pos : Position
  , focused : Bool
  }

type alias Records = Dict String Record

add : String -> Records -> Records
add id records =
  let
    rec = Record
      id
      ( Array.fromList [ "" ] )
      ( Array.fromList [ "" ] )
      ( Array.fromList [ "" ] )
      { x = 200, y = 200 }
      False
  in
    insert id rec records

newpair : Record -> Record
newpair rec =
  { rec
    | k = Array.push "" rec.k
    , v = Array.push "" rec.v
    , calc = Array.push "" rec.calc
  }


-- UPDATE


type RecordMsg
  = DragStart Position
  | DragAt Position
  | DragEnd Position
  | ChangeKey Int String
  | ChangeValue Int String
  | Focus
  | CalcResult Int String


update : RecordMsg -> Record -> (Record, Cmd RecordMsg)
update msg record =
  case msg of
    DragStart _ -> ( record, Cmd.none )
    DragAt pos -> ( { record | pos = pos }, Cmd.none )
    DragEnd _ -> ( record, Cmd.none )
    ChangeKey idx newk ->
      let
        nr = { record | k = record.k |> Array.set idx newk }
        nnr = if (Array.length nr.k) - 1 == idx then newpair nr else nr
      in ( nnr, Cmd.none )
    ChangeValue idx newv ->
      let
        nr =
          { record
            | v = record.v |> Array.set idx newv
            , calc = record.calc |> Array.set idx newv
          }
        nnr = if (Array.length nr.k) - 1 == idx then newpair nr else nr
      in ( nnr, Cmd.none )
    Focus -> ( { record | focused = True }, Cmd.none )
    CalcResult idx v ->
      ( { record | calc = record.calc |> Array.set idx v }
      , Cmd.none
      )


-- VIEW


view : Record -> Html RecordMsg
view rec =
  div
    [ class <| "record " ++ if rec.focused then "focused" else ""
    , on "mousedown"
      <| Decode.map DragStart
        <| Decode.map2 Position
          ( Decode.at [ "currentTarget", "parentNode", "offsetLeft" ] Decode.int )
          ( Decode.at [ "currentTarget", "parentNode", "offsetTop" ] Decode.int )
    , onMouseUp Focus
    , style
      [ "position" => "absolute"
      , "left" => px rec.pos.x
      , "top" => px rec.pos.y
      ]
    , title rec.id
    ]
    [ table [] <|
      List.map4 (viewKV rec.focused)
        ( List.range 0 ((Array.length rec.k) - 1) )
        ( Array.toList rec.k)
        ( Array.toList rec.v)
        ( Array.toList rec.calc)
    ]

viewKV : Bool -> Int -> String -> String -> String -> Html RecordMsg
viewKV focused idx k v calc =
  tr [] <|
    [ th []
      [ input
        [ value k
        , onInput <| ChangeKey idx
        , readonly <| not focused
        ] []
      ]
    , td []
      [ input
        [ value <| if focused then v else calc
        , onInput <| ChangeValue idx
        , readonly <| not focused
        ] []
      ]
    ]
