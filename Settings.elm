module Settings exposing (..)

import Html exposing
  ( Html, text, div, aside
  , p, ul, li, a
  )
import Html.Attributes exposing (class, value)
import Html.Events exposing (onClick, onInput)

import Record exposing (Record)


-- MODEL


type alias Settings =
  { kinds : List Kind
  }

type alias Kind =
  { id : Int
  , name : String
  , default_fields : List String
  }


-- toNormalRecord : Settings -> Record
-- toNormalRecord settings =
--   Record
--     "config"
--     ( Array.fromList
--       [ 
--       ]
--     )

-- UPDATE


type Msg
  = NewKind
  | SelectKind Int


update : Msg -> Settings -> (Settings, Cmd Msg)
update msg settings =
  case msg of
    NewKind -> ( settings, Cmd.none )
    SelectKind id -> ( settings, Cmd.none )


-- VIEW


view : Settings -> Html Msg
view settings =
  div [ class "columns" ]
    [ div [ class "column is-narrow" ]
      [ aside [ class "menu" ]
        [ p [ class "menu-label" ] [ text "Kinds" ]
        , ul [ class "menu-list" ]
          [ li []
            [ a [] [ text "Edit kinds" ]
            , ul []
              <| List.map (\k -> li [] [ a [ onClick <| SelectKind k.id ] [ text k.name ] ])
              <| settings.kinds
            ]
          , li [] [ a [ onClick NewKind ] [ text "Add new kind" ] ]
          ]
        , p [ class "menu-label" ] [ text "Menu Label" ]
        , ul [ class "menu-list" ]
          [ li [] [ a [] [ text "Dashboard" ] ]
          , li [] [ a [] [ text "Customers" ] ]
          ]
        ]
      ]
    , div [ class "column" ]
      [ div [ class "menu-body" ]
        [
        ]
      ]
    ]
