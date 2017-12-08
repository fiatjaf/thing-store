port module Ports exposing (..)

import Record exposing (..)


port changedValue : (String, Int, String) -> Cmd msg
port queueRecord : Record -> Cmd msg
port saveToPouch : () -> Cmd msg
port requestId : () -> Cmd msg

port notify : (String -> msg) -> Sub msg
port gotCalcResult : ((String, Int, String) -> msg) -> Sub msg
port gotId : (String -> msg) -> Sub msg
port gotPendingSaves : (Int -> msg) -> Sub msg
