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
import Html.Events exposing (on, onWithOptions, onInput, onDoubleClick)
import Html.Lazy exposing (..)
import Dict exposing (Dict, insert, get)
import Json.Decode as Decode exposing (decodeString)
import Array exposing (Array, slice)
import String exposing (split, trim)
import Task
import List exposing (drop, head)
import Mouse exposing (Position)
import Maybe.Extra exposing (..)
import ContextMenu
import Select

import Settings exposing (..)
import Helpers exposing (..)


-- MODEL


type alias Record =
  { id : String
  , name : Maybe String
  , k : Array String -- keys
  , v : Array String -- values
  , c : Array String -- calculated values (or error message)
  , e : Array Bool   -- if key calculation is errored
  , f : Array Field  -- field definitions
  , selects : Array (Maybe Select.State)
  , pos : Position
  , width : Int
  , kind : Maybe Int
  , focused : Bool
  }

type alias Field = { linked : Bool }
defaultField = { linked = False }

type alias RestrictedRecord =
  { id : String
  , k : Array String
  , v : Array String
  , c : Array String
  , e : Array Bool
  , f : Array Field
  , pos : Position
  , width : Int
  , kind : Maybe Int
  }

toRestricted : Record -> RestrictedRecord
toRestricted r =
  RestrictedRecord r.id r.k r.v r.c r.e r.f r.pos r.width r.kind

fromRestricted : RestrictedRecord -> Record
fromRestricted rr = Record
  rr.id
  ( findIndex "@name" (Array.toList rr.k) |> Maybe.map (\idx -> Array.get idx rr.c) |> join )
  rr.k
  rr.v
  rr.c
  rr.e
  rr.f
  ( Array.repeat (Array.length rr.k) Nothing )
  rr.pos
  rr.width
  rr.kind
  False

add : String -> Maybe Int -> Maybe (Array String) -> Dict String Record -> Dict String Record
add next_id kind default_keys records =
  let
    keys = Maybe.withDefault (Array.fromList [""]) default_keys
    nkeys = Array.length keys
    rec = Record
      next_id
      Nothing
      keys
      ( Array.repeat nkeys "" )
      ( Array.repeat nkeys "" )
      ( Array.repeat nkeys False )
      ( Array.repeat nkeys defaultField )
      ( Array.repeat nkeys Nothing )
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
    , f = Array.push defaultField rec.f
    , selects = Array.push Nothing rec.selects
  }

showRecord : Record -> String
showRecord record = record.name ? dumpPairs record

dumpPairs : Record -> String
dumpPairs rec =
  String.join ", "
    <| List.map (\(k,v) -> k ++ "=" ++ v)
    <| List.filter (\(k,v) -> trim k /= "" && trim v /= "")
    <| List.map2 (,)
      ( Array.toList rec.k )
      ( Array.toList rec.c )

selectConfig : Int -> Select.Config Msg Record
selectConfig idx =
  Select.newConfig (SelectLinked idx) showRecord
    |> Select.withCutoff 7
    |> Select.withMenuClass "select-menu"
    |> Select.withItemClass "select-item"
    |> Select.withHighlightedItemClass "highlighted"
    |> Select.withPrompt ""
    |> Select.withPromptClass "select-prompt"
    |> Select.withNotFoundShown False

type MenuContext
  = BackgroundContext
  | RecordContext Record
  | KeyValueContext Record Int


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
  | ChangeLinked Bool Int
  | EditLinked (String, Int)
  | Focus
  | CalcResult Int String
  | CalcError Int String
  | DeleteRow Int
  | SelectLinked Int (Maybe Record)
  | SelectAction Int (Select.Msg Record)
  | RecordContextMenuAction (ContextMenu.Msg MenuContext)
  | Noop


update : Msg -> Record -> (Record, Cmd Msg)
update msg record =
  case msg of
    DragAt pos -> ( { record | pos = pos }, Cmd.none )
    ResizeAt width -> ( { record | width = width }, Cmd.none )
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
            , e = record.e |> Array.set idx False
            , name = case Array.get idx record.k of
              Just "@name" -> Just newv
              _ -> record.name
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
    ChangeLinked linked idx ->
      ( { record
          | f = Array.get idx record.f
            |> Maybe.map (\f -> { f | linked = linked })
            |> Maybe.withDefault defaultField
            |> \field -> Array.set idx field record.f
        }
      , if linked
        then Task.succeed ()
          |> Task.perform (\() -> EditLinked (record.id, idx))
        else Cmd.none
      )
    Focus -> ( { record | focused = True }, Cmd.none )
    CalcResult idx v ->
      ( { record
          | c = record.c |> Array.set idx v
          , e = record.e |> Array.set idx False
          , name = case Array.get idx record.k of
            Just "@name" -> Just v
            _ -> record.name
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
    SelectLinked idx maybelinked ->
      ( record
      , case maybelinked of
        Nothing -> Cmd.none
        Just linked ->
          Task.succeed ()
            |> Task.perform (\() -> ChangeValue idx ("@" ++ linked.id))
      )
    SelectAction idx subMsg ->
      let
        state = ( join <| Array.get idx record.selects )
          ? Select.newState (record.id ++ "¬" ++ toString idx)
        (updated, cmd) = Select.update (selectConfig idx) subMsg state
      in
        ( { record | selects = record.selects |> Array.set idx (Just updated) }, cmd )
    RecordContextMenuAction msg -> ( record, Cmd.none )
    _ -> ( record, Cmd.none )


-- VIEW


viewFloating : Maybe Kind -> Record -> Html Msg
viewFloating mkind rec =
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
    , title <| unwrap "--no-kind--" .name mkind
    , ContextMenu.open RecordContextMenuAction (RecordContext rec)
    ]
    [ div [ class "id" ]
      [ span [ class "tag" ] [ text rec.id ]
      ]
    , table
        [ preventOrFocus rec
        , style [ ( "border-color", unwrap "" .color mkind ) ]
        ] <|
        List.map2 (lazy3 viewKV rec)
          ( List.range 0 ((Array.length rec.k) - 1) )
          ( List.map5 (\a b c d e -> (a, b, c, d, e))
            ( Array.toList rec.k )
            ( Array.toList rec.v )
            ( Array.toList rec.c )
            ( Array.toList rec.e )
            ( Array.toList rec.f )
          )
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

viewKV : Record -> Int -> (String, String, String, Bool, Field) -> Html Msg
viewKV rec idx (k,v,c,e,f) =
  tr
    [ ContextMenu.open RecordContextMenuAction (KeyValueContext rec idx)
    , class <| if f.linked then "linked" else ""
    ]
    [ th []
      [ input
        [ value k
        , onInput <| ChangeKey idx
        , readonly <| not rec.focused
        ] []
      ]
    , td [ class <| if e && not rec.focused then "error" else "", title c ]
      [ input
        [ value <| if rec.focused then v else if f.linked then rec.name ? v else c
        , onInput <| ChangeValue idx
        , if f.linked then onDoubleClick <| EditLinked (rec.id, idx) else attribute "n" ""
        , readonly <| not rec.focused
        ] []
      ]
    ]

viewLinkedValue : Dict String Record -> Record -> Int -> (String, String, String) -> Html Msg
viewLinkedValue records rec idx (key, value, calc) =
  div
    [ onWithOptions
        "click"
        { stopPropagation = True, preventDefault = False }
        ( Decode.succeed Noop )
    ]
    [ text key
    , text ": "
    , Html.map (SelectAction idx)
      <| Select.view
        ( selectConfig idx )
        ( ( join <| Array.get idx rec.selects )
        ? ( Select.newState (rec.id ++ "¬" ++ toString idx) )
        )
        ( Dict.values records )
        ( value
          |> split "@"
          |> drop 1
          |> head
          |> Maybe.map (flip Dict.get records)
          |> join
        )
    ]

viewRow : Maybe Kind -> List String -> Record -> Html Msg
viewRow mkind keys rec =
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
      , ContextMenu.open RecordContextMenuAction (RecordContext rec)
      , preventOrFocus rec
      , title <| unwrap "--no kind--" .name mkind
      , style [ ( "border-color", unwrap "" .color mkind ) ]
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
