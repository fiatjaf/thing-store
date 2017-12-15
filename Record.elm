module Record exposing (..)

import Html exposing
  ( Html, text , div
  , table, tr, td, th
  , input, span
  )
import Html.Attributes exposing
  ( class, style, value, readonly
  , title, attribute, style
  )
import Html.Events exposing (on, onWithOptions, onInput)
import Html.Lazy exposing (..)
import Dict exposing (Dict, insert, get)
import Json.Decode as Decode
import Array exposing (Array, slice)
import Mouse exposing (Position)
import ContextMenu

import Settings exposing (..)
import Menu exposing (..)
import Helpers exposing (..)


-- MODEL


type alias Record =
  { id : String
  , k : Array String -- keys
  , v : Array String -- values
  , c : Array String -- calculated values (or error message)
  , e : Array Bool   -- if key calculation is errored
  , pos : Position
  , width : Int
  , kind : Maybe Int
  , focused : Bool
  }

add : String -> Maybe Int -> Maybe (Array String) -> Dict String Record -> Dict String Record
add next_id kind default_keys records =
  let
    keys = Maybe.withDefault (Array.fromList [""]) default_keys
    nkeys = Array.length keys
    rec = Record
      next_id
      keys
      ( Array.repeat nkeys "" )
      ( Array.repeat nkeys "" )
      ( Array.repeat nkeys False )
      { x = 0, y = 0 }
      180
      kind
      False
  in
    insert next_id rec records

newpair : Record -> Record
newpair rec =
  { rec
    | k = Array.push "" rec.k
    , v = Array.push "" rec.v
    , c = Array.push "" rec.c
    , e = Array.push False rec.e
  }


-- UPDATE


type Msg
  = DragStart Position
  | DragAt Position
  | DragEnd Position
  | ResizeStart Int
  | ResizeAt Int
  | ResizeEnd Int
  | ChangeKey Int String
  | ChangeValue Int String
  | AddNewKVWithValue String String
  | ChangeKind (Maybe Int)
  | Focus
  | CalcResult Int String
  | CalcError Int String
  | DeleteRow Int
  | RecordContextMenuAction (ContextMenu.Msg Context)
  | Noop


update : Msg -> Record -> (Record, Cmd Msg)
update msg record =
  case msg of
    DragAt pos -> ( { record | pos = pos }, Cmd.none )
    ResizeAt width -> ( { record | width = width }, Cmd.none )
    ChangeKey idx newk ->
      let
        _ = Debug.log "idx" idx
        _ = Debug.log "k" record.k
        nr = { record | k = record.k |> Array.set idx newk }
        nnr = if (Array.length nr.k) - 1 == idx then newpair nr else nr
      in ( nnr, Cmd.none )
    ChangeValue idx newv ->
      let
        nr =
          { record
            | v = record.v |> Array.set idx newv
            , c = record.c |> Array.set idx newv
            , e = record.e |> Array.set idx False
          }
        nnr = if (Array.length nr.k) - 1 == idx then newpair nr else nr
      in ( nnr, Cmd.none )
    AddNewKVWithValue key newv ->
      ( { record
          | k = record.k |> Array.push key
          , v = record.v |> Array.push newv
          , c = record.c |> Array.push newv
          , e = record.e |> Array.push False
        }
      , Cmd.none
      )
    ChangeKind kind -> ( { record | kind = kind }, Cmd.none )
    Focus -> ( { record | focused = True }, Cmd.none )
    CalcResult idx v ->
      ( { record
          | c = record.c |> Array.set idx v
          , e = record.e |> Array.set idx False
        }
      , Cmd.none
      )
    CalcError idx message ->
      ( { record
          | c = record.c |> Array.set idx message
          , e = record.e |> Array.set idx True
        }
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
            , e = Array.append (slice 0 idx record.e) (slice (idx + 1) len record.e)
          }
        , Cmd.none
        )
    RecordContextMenuAction msg -> ( record, Cmd.none )
    _ -> ( record, Cmd.none )


-- VIEW


viewFloating : String -> Record -> Html Msg
viewFloating color rec =
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
      [ ( "position", "absolute" )
      , ( "left", px rec.pos.x )
      , ( "top", px rec.pos.y )
      , ( "width", (toString rec.width) ++ "px" )
      ]
    , title rec.id
    , ContextMenu.open RecordContextMenuAction (RecordContext rec.id)
    ]
    [ div [ class "id" ]
      [ span [ class "tag" ] [ text rec.id ]
      ]
    , table
        [ preventOrFocus rec
        , style [ ( "border-color", color ) ]
        ] <|
        List.map5 (viewKV rec)
          ( List.range 0 ((Array.length rec.k) - 1) )
          ( Array.toList rec.k)
          ( Array.toList rec.v)
          ( Array.toList rec.c)
          ( Array.toList rec.e)
    , if rec.focused
      then div
        [ class "resizer"
        , on "mousedown"
          <| Decode.map ResizeStart
            <| Decode.map (\x -> x - rec.width)
              ( Decode.field "pageX" Decode.int )
        ] []
      else text ""
    ]

viewKV : Record -> Int -> String -> String -> String -> Bool -> Html Msg
viewKV rec idx k v c e =
  tr [ ContextMenu.open RecordContextMenuAction (KeyValueContext rec.id idx) ]
    [ th []
      [ input
        [ value k
        , onInput <| ChangeKey idx
        , readonly <| not rec.focused
        ] []
      ]
    , td [ class <| if e && not rec.focused then "error" else "", title c ]
      [ input
        [ value <| if rec.focused then v else c
        , onInput <| ChangeValue idx
        , readonly <| not rec.focused
        ] []
      ]
    ]

viewRow : Array Kind -> List String -> Record -> Html Msg
viewRow kinds keys rec =
  let
    fetch key =
      findIndex key (Array.toList rec.k)
      |> Maybe.map
        (\idx ->
          ( idx
          , ( Array.get idx rec.v |> Maybe.withDefault "" )
          , ( Array.get idx rec.c |> Maybe.withDefault "" )
          , ( Array.get idx rec.e |> Maybe.withDefault False )
          )
        )
  in
    tr
      [ class <| "record " ++ if rec.focused then "focused" else ""
      , ContextMenu.open RecordContextMenuAction (RecordContext rec.id)
      , preventOrFocus rec
      ]
      <| (::) (th [] [ text rec.id ])
      <| List.map2 (lazy3 viewCell rec)
        ( keys )
        ( List.map fetch keys )

viewCell : Record -> String -> Maybe (Int, String, String, Bool) -> Html Msg
viewCell rec key celldata =
  case celldata of
    Just (idx, v, c, e) ->
      td
        [ class <| if e && not rec.focused then "error" else ""
        , title c
        ]
        [ input
          [ value <| if rec.focused then v else c
          , onInput <| ChangeValue idx
          , readonly <| not rec.focused
          ] []
        ]
    Nothing ->
      td [ class "unset" ]
        [ input
          [ onInput <| AddNewKVWithValue key
          , readonly <| not rec.focused
          ] []
        ]


-- HELPERS


preventOrFocus : Record -> Html.Attribute Msg
preventOrFocus rec = if rec.focused
  then onWithOptions -- when this is already focused, clicking it shouldn't trigger
    "mousedown"      -- the global "UnfocusAll" event, but default shouldn't be
    { stopPropagation = True, preventDefault = False } -- prevented, because it is
    ( Decode.succeed Noop ) -- needed to change the focus between <input>s
  else on -- when this is not focused, we want it to be focused no matter what.
    "mouseup"
    ( Decode.succeed Focus )
