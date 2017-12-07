module Menu exposing (..)

import ContextMenu exposing (ContextMenu)
import Color


type Context
  = BackgroundContext
  | RecordContext String
  | KeyValueContext String Int


config =
  { width = 200
  , direction = ContextMenu.RightBottom
  , overflowX = ContextMenu.Mirror
  , overflowY = ContextMenu.Mirror
  , containerColor = Color.white
  , hoverColor = Color.rgb 240 240 240
  , invertText = False
  , cursor = ContextMenu.Pointer
  , rounded = False
  , fontFamily = "inherit"
  }
