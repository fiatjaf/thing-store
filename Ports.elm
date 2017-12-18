port module Ports exposing (..)

import Record exposing (..)
import Settings exposing (..)


port changedValue : (String, Int, String) -> Cmd msg
port changedKind : (String, Maybe Int, Maybe Int) -> Cmd msg
port changedConfig : Config -> Cmd msg
port runView : String -> Cmd msg
port queueSaveRecord : RestrictedRecord -> Cmd msg
port saveConfig : Config -> Cmd msg
port saveToPouch : () -> Cmd msg
port requestId : () -> Cmd msg

queueRecord = toRestricted >> queueSaveRecord

port notify : (String -> msg) -> Sub msg
port replaceRecords : (List RestrictedRecord -> msg) -> Sub msg
port gotCalcResult : ((String, Int, String) -> msg) -> Sub msg
port gotCalcError : ((String, Int, String) -> msg) -> Sub msg
port gotId : (String -> msg) -> Sub msg
port gotPendingSaves : (Int -> msg) -> Sub msg
