module Settings exposing (..)

import Html exposing
  ( Html, text, div, aside
  , p, ul, li, a, h2
  , label, input, button
  )
import Html.Attributes exposing (class, value, style, type_)
import Html.Events exposing (onClick, onInput)
import Array exposing (Array)
import Hashbow exposing (hashbow)

import Menu exposing (..)


-- MODEL


type alias Settings =
  { config : Config
  , section : Maybe Section
  }

defaultSettings = Settings (Config Array.empty) Nothing

type alias Config =
  { kinds : Array Kind
  }

type alias Kind =
  { name : String
  , color : String
  , default_fields : Array String
  }

grabColor : Array Kind -> { a | kind : Maybe Int } -> String
grabColor kinds kindable =
  kindable.kind
  |> Maybe.map
    (\kindIndex -> Array.get kindIndex kinds |> Maybe.map .color |> Maybe.withDefault "")
  |> Maybe.withDefault ""

emptyKind = Kind "" "" Array.empty

type Section
  = KindSection Int


-- UPDATE


type Msg
  = NewKind
  | SelectKind Int
  | KindAction Int KindMsg

type KindMsg
  = KindName String
  | KindField Int String
  | KindColor String
  | SaveKind


update : Msg -> Settings -> (Settings, Cmd Msg)
update msg settings =
  case msg of
    NewKind ->
      let 
        config = settings.config
        emptykinds = settings.config.kinds
          |> Array.toList
          |> List.indexedMap (,)
          |> List.filter (Tuple.second >> .name >> (==) "")
        (kinds,index) = case emptykinds of
          [] ->
            let
              i = Array.length settings.config.kinds
              color = hashbow <| toString i
            in
              ( settings.config.kinds |> Array.push { emptyKind | color = color }
              , i
              )
          (i,_)::_ -> ( settings.config.kinds, i )
      in
        ( { settings
            | section = Just (KindSection index)
            , config = { config | kinds = kinds }
          }
        , Cmd.none
        )
    SelectKind i -> ( { settings | section = Just <| KindSection i }, Cmd.none )
    KindAction i msg ->
      let
        kind : Maybe Kind
        kind = settings.config.kinds
          |> Array.get i
          |> Maybe.map
            (\kind -> case msg of
              KindName name -> { kind | name = name }
              KindColor color -> { kind | color = color }
              KindField index value ->
                { kind | default_fields = kind.default_fields
                  |> ( if (index < (Array.length kind.default_fields))
                       then Array.set index value
                       else Array.push value
                     )
                  |> Array.filter (not << (==) "")
                }
              _ -> kind
            )
        kinds : Array Kind
        kinds = case kind of
          Nothing -> settings.config.kinds
          Just kind -> Array.set i kind settings.config.kinds

        config = settings.config
      in
        ( { settings | config = { config | kinds = kinds } }
        , Cmd.none
        )


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
            , ul [ class "kinds" ]
              <| List.indexedMap
                (\i kind ->
                  li []
                    [ a
                      [ onClick <| SelectKind i
                      , style [ ( "background-color", kind.color ) ]
                      , class <|
                        if settings.section == Just (KindSection i)
                        then "is-active"
                        else ""
                      ] [ text kind.name ]
                    ]
                )
              <| Array.toList
              <| settings.config.kinds
            ]
           , li [] [ a [ onClick NewKind ] [ text "Add new kind" ] ]
          ]
        , p [ class "menu-label" ] [ text "Views" ]
        , ul [ class "menu-list" ]
          [ li [] [ a [] [ text "Edit views" ] ]
          , li [] [ a [] [ text "New view" ] ]
          ]
        ]
      ]
    , div [ class "column" ]
      [ div [ class "menu-body" ]
        [ case settings.section of
          Nothing -> div [] []
          Just (KindSection i) -> settings.config.kinds
            |> Array.get i
            |> Maybe.map (viewKindEdit i)
            |> Maybe.withDefault (div [] [])
            |> Html.map (KindAction i)
        ]
      ]
    ]

viewKindEdit : Int -> Kind -> Html KindMsg
viewKindEdit i kind =
  div []
    [ div [ class "field is-horizontal" ]
      [ div [ class "field-label" ] []
      , div [ class "field-body" ]
        [ h2 [ class "title" ] [ text <| "kind " ++ kind.name ++ " (" ++ toString i ++ ")" ]
        ]
      ]
    , div [ class "field is-horizontal" ]
      [ div [ class "field-label" ] [ label [] [ text "Name: " ] ]
      , div [ class "field-body" ]
        [ input [ class "input", value kind.name, onInput KindName ] []
        ]
      ]
    , div [ class "field is-horizontal" ]
      [ div [ class "field-label" ] [ label [] [ text "Color: " ] ]
      , div [ class "field-body" ]
        [ input [ class "input", type_ "color", value kind.color, onInput KindColor ] []
        ]
      ]
    , div [ class "field is-horizontal" ]
      [ div [ class "field-label" ] [ label [] [ text "Default fields: " ] ]
      , div [ class "field-body" ]
        <| Array.toList
        <| Array.indexedMap
          (\index v ->
            div []
              [ input [ class "input", value v, onInput <| KindField index ] []
              ]
          )
        <| Array.push ""
        <| kind.default_fields
      ]
    , div [ class "field is-horizontal" ]
      [ div [ class "field-label" ] []
      , div [ class "field-body" ]
        [ button [ class "button is-primary", onClick SaveKind ] [ text "Save" ]
        ]
      ]
    ]
