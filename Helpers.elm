module Helpers exposing (..)

import Mouse exposing (Position)


(=>) = (,)

px : Int -> String
px number =
  toString number ++ "px"
