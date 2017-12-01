import Html exposing
  ( Html, text , div
  )
import Html.Lazy exposing (..)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick, onInput)
import Dict exposing (Dict)
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
  , Cmd.batch
    [ requestId ()
    ]
  )


-- UPDATE


type Msg
  = NextBlankId String
  | Noop

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    NextBlankId id -> ( { model | next_blank_id = id }, Cmd.none )
    Noop -> ( model, Cmd.none )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ gotId NextBlankId
    ]


-- VIEW


view : Model -> Html Msg
view model =
  div []
    [ text "data at \"~\""
    , div []
      [ text <| "next id: " ++ model.next_blank_id
      ]
    , div [ class "record-container" ] <|
      List.map (lazy Record.view)
        <| Dict.values model.records
    ]
