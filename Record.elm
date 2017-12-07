module Record exposing (..)

import Html exposing
  ( Html, text , div
  , table, tr, td, th
  , input, span
  )
import Html.Attributes exposing
  ( class, style, value, readonly
  , title, attribute
  )
import Html.Events exposing (on, onWithOptions, onInput)
import Dict exposing (Dict, insert, get)
import Json.Decode as Decode
import Array exposing (Array, slice)
import Mouse exposing (Position)
import ContextMenu

import Menu exposing (..)
import Helpers exposing (..)


-- MODEL


type alias Record =
  { id : String
  , k : Array String
  , v : Array String
  , c : Array String
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
      { x = 0, y = 0 }
      False
  in
    insert id rec records

fromTemplate : String -> Record -> Record
fromTemplate next_id rec =
  let
    keys = rec.k
    nkeys = Array.length keys
  in
    Record
      next_id
      keys
      ( Array.repeat nkeys "" )
      ( Array.repeat nkeys "" )
      { x = 0, y = 0 }
      False

newpair : Record -> Record
newpair rec =
  { rec
    | k = Array.push "" rec.k
    , v = Array.push "" rec.v
    , c = Array.push "" rec.c
  }


-- UPDATE


type Msg
  = DragStart Position
  | DragAt Position
  | DragEnd Position
  | ChangeKey Int String
  | ChangeValue Int String
  | Focus
  | CalcResult Int String
  | DeleteRow Int
  | RecordContextMenuAction (ContextMenu.Msg Context)
  | Noop


update : Msg -> Record -> (Record, Cmd Msg)
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
            , c = record.c |> Array.set idx newv
          }
        nnr = if (Array.length nr.k) - 1 == idx then newpair nr else nr
      in ( nnr, Cmd.none )
    Focus -> ( { record | focused = True }, Cmd.none )
    CalcResult idx v ->
      ( { record | c = record.c |> Array.set idx v }
      , Cmd.none
      )
    DeleteRow idx ->
      let
        len = Array.length record.k
      in
        ( { record
            | k = Array.append (slice 0 idx record.k) (slice (idx + 1) len record.k)
            , v = Array.append (slice 0 idx record.v) (slice (idx + 1) len record.v)
            , c = Array.append (slice 0 idx record.c) (slice (idx + 1) len record.c)
          }
        , Cmd.none
        )
    RecordContextMenuAction msg -> ( record, Cmd.none )
    Noop -> ( record, Cmd.none )


-- VIEW


view : Record -> Html Msg
view rec =
  div
    [ class <| "record " ++ if rec.focused then "focused" else ""
    , if rec.focused then attribute "n" "" else on "mousedown"
      -- dragging should only be triggered to an initially unfocused
      -- record, otherwise it would mess up with the native editing
      -- capabilities of <inputs>, like double-clicking to select all
      -- and clicking-and-dragging to select some of the text.
      <| Decode.map DragStart
        <| Decode.map2
          (\x y -> { x = x - rec.pos.x, y = y - rec.pos.y } )
          ( Decode.field "pageX" Decode.int )
          ( Decode.field "pageY" Decode.int )
    , style
      [ "position" => "absolute"
      , "left" => px rec.pos.x
      , "top" => px rec.pos.y
      ]
    , title rec.id
    , ContextMenu.open RecordContextMenuAction (RecordContext rec.id)
    ]
    [ div [ class "id" ]
      [ span [ class "tag" ] [ text rec.id ]
      ]
    , table
      [ if rec.focused
        then onWithOptions -- when this is already focused, clicking it shouldn't trigger
          "mousedown"      -- the global "UnfocusAll" event, but default shouldn't be
          { stopPropagation = True, preventDefault = False } -- prevented, because it is
          ( Decode.succeed Noop ) -- needed to change the focus between <input>s
        else on -- when this is not focused, we want it to be focused no matter what.
          "mouseup"
          ( Decode.succeed Focus )
      ] <|
        List.map4 (viewKV rec)
          ( List.range 0 ((Array.length rec.k) - 1) )
          ( Array.toList rec.k)
          ( Array.toList rec.v)
          ( Array.toList rec.c)
    ]

viewKV : Record -> Int -> String -> String -> String -> Html Msg
viewKV rec idx k v c =
  tr
    [ ContextMenu.open RecordContextMenuAction (KeyValueContext rec.id idx)
    ]
    [ th []
      [ input
        [ value k
        , onInput <| ChangeKey idx
        , readonly <| not rec.focused
        ] []
      ]
    , td []
      [ input
        [ value <| if rec.focused then v else c
        , onInput <| ChangeValue idx
        , readonly <| not rec.focused
        ] []
      ]
    ]
