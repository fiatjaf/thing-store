port module Ports exposing (..)

import Record exposing (..)
import Settings exposing (..)


port changedValue : (String, Int, String) -> Cmd msg
port runView : String -> Cmd msg
port queueRecord : Record -> Cmd msg
port saveConfig : Config -> Cmd msg
port saveToPouch : () -> Cmd msg
port requestId : () -> Cmd msg

port notify : (String -> msg) -> Sub msg
port replaceRecords : (List Record -> msg) -> Sub msg
port gotCalcResult : ((String, Int, String) -> msg) -> Sub msg
port gotCalcError : ((String, Int, String) -> msg) -> Sub msg
port gotId : (String -> msg) -> Sub msg
port gotPendingSaves : (Int -> msg) -> Sub msg
