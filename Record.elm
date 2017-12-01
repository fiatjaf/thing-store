module Record exposing (..)

import Html exposing
  ( Html, text , div
  , table, tr, td, th
  , input
  )
import Html.Attributes exposing (class, style)
import Html.Events exposing (onClick, onInput)
import Dict exposing (Dict)
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
      { x=23, y=18 }
  in
    Dict.insert id rec records


-- VIEW


view : Record -> Html msg
view rec =
  div
    [ class "record"
    , style
      [ "position" => "absolute"
      , "left" => px rec.pos.x
      , "top" => px rec.pos.y
      ]
    ]
    [ table [] <|
      List.map viewKV rec.kv
    ]

viewKV : ( String, String ) -> Html msg
viewKV (k, v) =
  tr []
    [ th [] [ text k ]
    , td [] [ text v ]
    ]
