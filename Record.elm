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
import Maybe.Extra exposing (..)
import ContextMenu
import Select

import Settings exposing (..)
import Helpers exposing (..)


-- MODEL


type alias Record =
  { id : String
  , k : Array String -- keys
  , v : Array String -- values
  , c : Array String -- calculated values (or error message)
  , e : Array Bool   -- if key calculation is errored
  , l : Array Bool   -- if kv should be considered a link to an external record
  , pos : Position
  , width : Int
  , kind : Maybe Int
  , focused : Bool
  , select_state : Select.State
  }

type alias RestrictedRecord =
  { id : String
  , k : Array String
  , v : Array String
  , c : Array String
  , e : Array Bool
  , l : Array Bool
  , pos : Position
  , width : Int
  , kind : Maybe Int
  }

toRestricted : Record -> RestrictedRecord
toRestricted r =
  RestrictedRecord r.id r.k r.v r.c r.e r.l r.pos r.width r.kind

fromRestricted : RestrictedRecord -> Record
fromRestricted rr = Record
  rr.id
  rr.k
  rr.v
  rr.c
  rr.e
  rr.l
  rr.pos
  rr.width
  rr.kind
  False
  ( Select.newState rr.id )

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
      ( Array.repeat nkeys False )
      { x = 0, y = 0 }
      180
      kind
      False
      ( Select.newState next_id )
  in
    insert next_id rec records

newpair : Record -> Record
newpair rec =
  { rec
    | k = Array.push "" rec.k
    , v = Array.push "" rec.v
    , c = Array.push "" rec.c
    , e = Array.push False rec.e
    , l = Array.push False rec.l
  }

selectConfig : Select.Config Msg Record
selectConfig =
  Select.newConfig SelectLinked .id
    |> Select.withCutoff 5
    |> Select.withInputStyles [ ( "padding", "0.5rem" ), ( "outline", "none" ) ]
    |> Select.withItemClass "border-bottom border-silver p1 gray"
    |> Select.withItemStyles [ ( "font-size", "1rem" ) ]
    |> Select.withMenuClass "border border-gray"
    |> Select.withMenuStyles [ ( "background", "white" ) ]
    |> Select.withNotFoundShown False
    |> Select.withHighlightedItemClass "bg-silver"
    |> Select.withHighlightedItemStyles [ ( "color", "black" ) ]
    |> Select.withPrompt "CHOOSE: "
    |> Select.withPromptClass "grey"

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
  | Focus
  | CalcResult Int String
  | CalcError Int String
  | DeleteRow Int
  | SelectLinked (Maybe Record)
  | SelectAction (Select.Msg Record)
  | RecordContextMenuAction (ContextMenu.Msg MenuContext)
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
    ChangeLinked linked idx ->
      ( { record | l = record.l |> Array.set idx linked }
      , Cmd.none
      )
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
    SelectLinked mrecord -> ( record, Cmd.none )
    SelectAction subMsg ->
      let (updated, cmd) = Select.update selectConfig subMsg record.select_state
      in ( { record | select_state = updated }, cmd )
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
        List.map4 (viewKV rec)
          ( List.range 0 ((Array.length rec.k) - 1) )
          ( Array.toList rec.k)
          ( List.map2 (,) ( Array.toList rec.v) ( Array.toList rec.c) )
          ( List.map2 (,) ( Array.toList rec.e) ( Array.toList rec.l ) )
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

viewKV : Record -> Int -> String -> (String, String) -> (Bool, Bool) -> Html Msg
viewKV rec idx k (v,c) (e,l) =
  tr
    [ ContextMenu.open RecordContextMenuAction (KeyValueContext rec idx)
    , class <| if l then "linked" else ""
    ]
    [ th []
      [ input
        [ value k
        , onInput <| ChangeKey idx
        , readonly <| not rec.focused
        ] []
      ]
    , td [ class <| if e && not rec.focused then "error" else "", title c ] <|
      [ if l 
        then
          Html.map SelectAction
            ( Select.view selectConfig rec.select_state [] Nothing)
        else
          input
            [ value <| if rec.focused then v else c
            , onInput <| ChangeValue idx
            , readonly <| not rec.focused
            ] []
      ]
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
