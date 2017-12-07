module Helpers exposing (..)

import Mouse exposing (Position)


(=>) = (,)

px : Int -> String
px number =
  toString number ++ "px"

findIndex = findIndexStartingSomewhere 0

findIndexStartingSomewhere : Int -> a -> List a -> Maybe Int
findIndexStartingSomewhere start_at elem list =
  case list of
    [] -> Nothing
    first::rest ->
      if first == elem
      then Just start_at
      else findIndexStartingSomewhere (start_at + 1) elem rest
