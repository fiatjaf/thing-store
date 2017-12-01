port module Ports exposing (..)

import Record exposing (..)


port calc : String -> Cmd msg
port queueRecord : Record -> Cmd msg
port saveToPouch : () -> Cmd msg
port requestId : () -> Cmd msg

port gotCalcResult : (String -> msg) -> Sub msg
port gotSaveResult : (String -> msg) -> Sub msg
port gotId : (String -> msg) -> Sub msg
port gotPendingSaves : (Int -> msg) -> Sub msg
