effect module Postgres
    where { command = MyCmd, subscription = MySub }
    exposing
        ( connect
        , disconnect
        , query
        , moreQueryResults
        , executeSql
        , serverSideConfig
        , clientSideConfig
        , listen
        , isOnClient
        , debug
        , dumpState
        , ErrorTagger
        , QueryTagger
        , ConnectionId
        , ListenChannel
        , Sql
        , WSUrl
        , ListenUnlisten(..)
        )

{-| Postgres Effects Manager to access Postgres DBs

The native driver is https://github.com/brianc/node-postgres.

# Helpers
@docs isOnClient

# Commands
@docs connect, disconnect, query, moreQueryResults, executeSql, serverSideConfig, clientSideConfig, debug, dumpState

# Subscriptions
@docs listen

# Types
@docs ErrorTagger, QueryTagger, ConnectionId, ListenChannel, Sql, WSUrl, ListenUnlisten
-}

import Task exposing (Task)
import Dict exposing (Dict)
import StringUtils exposing (..)
import DebugF exposing (toStringF)
import Native.Postgres
import Utils.Ops exposing (..)


-- Helpers


{-| check to see if we're running on the client, i.e. using PGProxy (or something like it)
-}
isOnClient : Bool
isOnClient =
    Native.Postgres.isOnClient



-- API


type MyCmd msg
    = Connect (ErrorTagger msg) (ConnectTagger msg) (ConnectionLostTagger msg) TimeoutInSec String Int String String String
    | Disconnect (ErrorTagger msg) (DisconnectTagger msg) ConnectionId Bool
    | Query (ErrorTagger msg) (QueryTagger msg) ConnectionId Sql Int
    | MoreQueryResults (ErrorTagger msg) (QueryTagger msg) ConnectionId
    | ExecuteSql (ErrorTagger msg) (ExecuteTagger msg) ConnectionId Sql
    | ServerSideConfig (ConfigErrorTagger msg) (ConfigTagger msg) Int
    | ClientSideConfig (ConfigErrorTagger msg) (ConfigTagger msg) (BadResponseTagger msg) (Maybe WSUrl) (Maybe JsonString)
    | Debug Bool
    | DumpState


type MySub msg
    = Listen (ErrorTagger msg) (ListenTagger msg) (ListenEventTagger msg) ConnectionId ListenChannel



-- Types


{-| Native structure (opaque type)
-}
type Client
    = Client


{-| Native structure (opaque type)
-}
type Stream
    = Stream


{-| Native structure (opaque type)
-}
type NativeListener
    = NativeListener


{-| Connection id
-}
type alias ConnectionId =
    Int


{-| Listen channel
-}
type alias ListenChannel =
    String


{-| Sql command
-}
type alias Sql =
    String


{-| Websocket URL
-}
type alias WSUrl =
    String


{-| Timeout in seconds
-}
type alias TimeoutInSec =
    Int


{-| Listening type
-}
type ListenUnlisten
    = ListenType
    | UnlistenType


type alias JsonString =
    String



-- Taggers


{-| Error tagger
-}
type alias ErrorTagger msg =
    ( ConnectionId, String ) -> msg


type alias ConnectTagger msg =
    ConnectionId -> msg


type alias ConnectionLostTagger msg =
    ( ConnectionId, String ) -> msg


type alias DisconnectTagger msg =
    ConnectionId -> msg


{-| Successful Query tagger
-}
type alias QueryTagger msg =
    ( ConnectionId, List String ) -> msg


type alias ExecuteTagger msg =
    ( ConnectionId, Int ) -> msg


type alias ConfigErrorTagger msg =
    String -> msg


type alias ConfigTagger msg =
    () -> msg


type alias BadResponseTagger msg =
    ( String, String ) -> msg



-- State


type alias Connection msg =
    { connectionLostTagger : ConnectionLostTagger msg
    , connectionTagger : ConnectTagger msg
    , errorTagger : ErrorTagger msg
    , nativeListener : Maybe NativeListener
    , disconnectionTagger : Maybe (ConnectTagger msg)
    , queryTagger : Maybe (QueryTagger msg)
    , executeTagger : Maybe (ExecuteTagger msg)
    , listenTagger : Maybe (ListenTagger msg)
    , eventTagger : Maybe (ListenEventTagger msg)
    , client : Maybe Client
    , stream : Maybe Stream
    , recordCount : Maybe Int
    , sql : Maybe Sql
    }


type alias ListenerState msg =
    { channel : String
    , errorTagger : ErrorTagger msg
    , listenTagger : ListenTagger msg
    , eventTagger : ListenEventTagger msg
    }


type alias ListenerDict msg =
    Dict ConnectionId (ListenerState msg)


type alias NativeListenerDict =
    Dict ConnectionId NativeListener


{-| Effects manager state
-}
type alias State msg =
    { nextId : ConnectionId
    , connections : Dict ConnectionId (Connection msg)
    , listeners : ListenerDict msg
    , nativeListeners : NativeListenerDict
    , debug : Bool
    }



-- Operators


(&>) : Task x a -> Task x b -> Task x b
(&>) t1 t2 =
    t1 |> Task.andThen (\_ -> t2)


(&>>) : Task x a -> (a -> Task x b) -> Task x b
(&>>) t1 f =
    t1 |> Task.andThen f



-- Init


init : Task Never (State msg)
init =
    Task.succeed (State 0 Dict.empty Dict.empty Dict.empty False)



-- Cmds


cmdMap : (a -> b) -> MyCmd a -> MyCmd b
cmdMap f cmd =
    case cmd of
        Connect errorTagger tagger connectionLostTagger timeoutInSec host port_ database user password ->
            Connect (f << errorTagger) (f << tagger) (f << connectionLostTagger) timeoutInSec host port_ database user password

        Disconnect errorTagger tagger client discardConnection ->
            Disconnect (f << errorTagger) (f << tagger) client discardConnection

        Query errorTagger tagger connectionId sql recordCount ->
            Query (f << errorTagger) (f << tagger) connectionId sql recordCount

        MoreQueryResults errorTagger tagger connectionId ->
            MoreQueryResults (f << errorTagger) (f << tagger) connectionId

        ExecuteSql errorTagger tagger connectionId sql ->
            ExecuteSql (f << errorTagger) (f << tagger) connectionId sql

        ServerSideConfig errorTagger tagger maxPoolConnections ->
            ServerSideConfig (f << errorTagger) (f << tagger) maxPoolConnections

        ClientSideConfig errorTagger tagger badResponseTagger wsUrl json ->
            ClientSideConfig (f << errorTagger) (f << tagger) (f << badResponseTagger) wsUrl json

        Debug debug ->
            Debug debug

        DumpState ->
            DumpState



-- commands


{-| Connect to a database

    Usage:
        connect ErrorConnect SuccessConnect ConnectionLost 15 myHost 5432 myDb userName password

    where:
        ErrorConnect, SuccessConnect and ConnectionLost are your application's messages to handle the different scenarios
-}
connect : ErrorTagger msg -> ConnectTagger msg -> ConnectionLostTagger msg -> TimeoutInSec -> String -> Int -> String -> String -> String -> Cmd msg
connect errorTagger tagger connectionLostTagger timeoutInSec host port_ database user password =
    command (Connect errorTagger tagger connectionLostTagger timeoutInSec host port_ database user password)


{-| Disconnect from database

    Usage:
        disconnect ErrorDisconnect SuccessDisconnect 123 False

    where:
        ErrorDisconnect and SuccessDisconnect are your application's messages to handle the different scenarios
        123 is the connection id from the (ConnectTagger msg) handler
        False means to NOT discard the connection, i.e. return it into the pool
-}
disconnect : ErrorTagger msg -> DisconnectTagger msg -> ConnectionId -> Bool -> Cmd msg
disconnect errorTagger tagger connectionId discardConnection =
    command (Disconnect errorTagger tagger connectionId discardConnection)


{-| Query the database

    Usage:
        query ErrorQuery SuccessQuery 123 "SELECT * FROM table" 1000

    where:
        ErrorQuery and SuccessQuery are your application's messages to handle the different scenarios
        123 is the connection id from the (ConnectTagger msg) handler
        "SELECT * FROM table" is the SQL Command that returns a SINGLE result set
        1000 is the number of records or rows to return in this call and subsequent Postgres.moreQueryResults calls
-}
query : ErrorTagger msg -> QueryTagger msg -> ConnectionId -> Sql -> Int -> Cmd msg
query errorTagger tagger connectionId sql recordCount =
    command (Query errorTagger tagger connectionId sql recordCount)


{-| Get more records from the database based on the last call to Postgres.query

    Usage:
        moreQueryResults ErrorQuery SuccessQuery 123

    where:
        ErrorQuery and SuccessQuery are your application's messages to handle the different scenarios:
            when (snd SuccessQuery) == [] then there are no more records
        123 is the connection id from the (ConnectTagger msg) handler
-}
moreQueryResults : ErrorTagger msg -> QueryTagger msg -> ConnectionId -> Cmd msg
moreQueryResults errorTagger tagger connectionId =
    command (MoreQueryResults errorTagger tagger connectionId)


{-| Execute SQL command, e.g. INSERT, UPDATE, DELETE, etc.

    Usage:
        executeSql ErrorExecuteSql SuccessExecuteSql 123 "DELETE FROM table"

    where:
        ErrorExecuteSql and SuccessExecuteSql are your application's messages to handle the different scenarios
        123 is the connection id from the (ConnectTagger msg) handler
        "DELETE FROM table" is the SQL Command that returns a ROW COUNT
-}
executeSql : ErrorTagger msg -> ExecuteTagger msg -> ConnectionId -> Sql -> Cmd msg
executeSql errorTagger tagger connectionId sql =
    command (ExecuteSql errorTagger tagger connectionId sql)


{-| Server side configuration

    Max pool size should be set before any connections are made to a unique connection, i.e. [host, port, database, user] each of which has its own pool.

    Usage:
        serverSideConfig ConfigError Configured 200

    where:
        ConfigError, Configured and BadResponse are your application's messages to handle the different scenarios
        200 is the maximum number of pooled connections in a single pool
-}
serverSideConfig : ConfigErrorTagger msg -> ConfigTagger msg -> Int -> Cmd msg
serverSideConfig errorTagger tagger maxPoolConnections =
    command (ServerSideConfig errorTagger tagger maxPoolConnections)


{-| Client side configuration

    Usage:
        clientSideConfig ConfigError Configured BadResponse (Just "ws://pg-proxy-server") (Just "{\"sessionId\": \"1f137f5f-43ec-4393-b5e8-bf195015e697\"}")

    where:
        ConfigError, Configured and BadResponse are your application's messages to handle the different scenarios
        "ws:/pg-proxy-server" is the URL to the Websocket for the PG Proxy (all new connections will use this URL)
        "{\"sessionId\": \"1f137f5f-43ec-4393-b5e8-bf195015e697\"}" is the JSON string of an object to be merged with all requests
-}
clientSideConfig : ConfigErrorTagger msg -> ConfigTagger msg -> BadResponseTagger msg -> Maybe WSUrl -> Maybe JsonString -> Cmd msg
clientSideConfig errorTagger tagger badResponseTagger url json =
    command (ClientSideConfig errorTagger tagger badResponseTagger url json)


{-| Control debugging
-}
debug : Bool -> Cmd msg
debug debug =
    command (Debug debug)


{-| Dump state
-}
dumpState : Cmd msg
dumpState =
    command (DumpState)



-- subscription taggers


{-| Tagger for a successful listen/unlisten
-}
type alias ListenTagger msg =
    ( ConnectionId, ListenChannel, ListenUnlisten ) -> msg


{-| Tagger for a listen event
-}
type alias ListenEventTagger msg =
    ( ConnectionId, ListenChannel, String ) -> msg


subMap : (a -> b) -> MySub a -> MySub b
subMap f sub =
    case sub of
        Listen errorTagger listenTagger eventTagger connectionId channel ->
            Listen (f << errorTagger) (f << listenTagger) (f << eventTagger) connectionId channel



-- subscriptions


{-| Subscribe to Postgres NOTIFY messages (see https://www.postgresql.org/docs/current/static/sql-notify.html)

    Usage:
        listen ErrorListenUnlisten SuccessListenUnlisten ListenEvent 123 "myChannel"

    where:
        ErrorListenUnlisten, SuccessListenUnlisten and `ListenEvent` are your application's messages to handle the different scenarios
            Messages are sent to the application upon subscribe and unsubscribe (Listen and Unlisten)
        123 is the connection id from the (ConnectTagger msg) handler
        "myChannel" is the name of the Channel that will publish a STRING payload
-}
listen : ErrorTagger msg -> ListenTagger msg -> ListenEventTagger msg -> ConnectionId -> ListenChannel -> Sub msg
listen errorTagger listenTagger eventTagger connectionId channel =
    subscription (Listen errorTagger listenTagger eventTagger connectionId channel)



-- effect managers API


onEffects : Platform.Router msg (Msg msg) -> List (MyCmd msg) -> List (MySub msg) -> State msg -> Task Never (State msg)
onEffects router cmds subs state =
    let
        ( listeners, subErrorTasks ) =
            List.foldl (addMySub router state) ( Dict.empty, [] ) subs

        stoppedListening =
            Dict.diff state.listeners listeners

        startedListening =
            Dict.diff listeners state.listeners

        keptListening =
            Dict.diff state.listeners stoppedListening

        handleOneCmd state cmd tasks =
            let
                ( task, newState ) =
                    handleCmd router state cmd
            in
                ( task :: tasks, newState )

        ( tasks, cmdState ) =
            List.foldl (\cmd ( tasks, state ) -> handleOneCmd state cmd tasks) ( [], state ) cmds

        cmdTask =
            Task.sequence (List.reverse tasks)

        ( stopTask, stopState ) =
            stopListeners router stoppedListening cmdState

        ( startTask, startState ) =
            startListeners router startedListening stopState
    in
        cmdTask
            &> stopTask
            &> startTask
            &> Task.sequence (List.reverse <| subErrorTasks)
            &> Task.succeed { startState | listeners = listeners }


startStopListeners :
    (ErrorTagger msg -> ListenChannel -> ListenUnlisten -> ConnectionId -> String -> Msg msg)
    -> (ListenChannel -> ListenUnlisten -> ConnectionId -> NativeListener -> Msg msg)
    -> ListenUnlisten
    -> Platform.Router msg (Msg msg)
    -> ListenerDict msg
    -> State msg
    -> ( Task Never (), State msg )
startStopListeners errorListenUnlisten successListenUnlisten listenUnlisten router listeners state =
    let
        startStopListener connectionId listenerState ( task, state ) =
            let
                ( executeTask, executeState ) =
                    let
                        nativeListener =
                            Dict.get connectionId state.nativeListeners

                        errorTaggerCtor =
                            errorListenUnlisten listenerState.errorTagger listenerState.channel listenUnlisten connectionId

                        getTask connection type_ =
                            let
                                settings =
                                    (settings1 router
                                        errorTaggerCtor
                                        (successListenUnlisten listenerState.channel type_ connectionId)
                                    )
                            in
                                case type_ of
                                    ListenType ->
                                        Native.Postgres.listen settings connection.client listenerState.channel (Platform.sendToSelf router << ListenEvent connectionId listenerState.channel)

                                    UnlistenType ->
                                        Native.Postgres.unlisten settings connection.client listenerState.channel nativeListener
                    in
                        (Dict.get connectionId state.connections)
                            |?> (\connection ->
                                    ( getTask connection listenUnlisten
                                    , updateConnection state
                                        connectionId
                                        { connection
                                            | listenTagger = Just listenerState.listenTagger
                                            , eventTagger = Just listenerState.eventTagger
                                        }
                                    )
                                )
                            ?= ( Platform.sendToSelf router <| errorTaggerCtor "Invalid connectionId", state )
            in
                ( executeTask &> task, executeState )
    in
        Dict.foldl startStopListener ( Task.succeed (), state ) listeners


stopListeners : Platform.Router msg (Msg msg) -> ListenerDict msg -> State msg -> ( Task Never (), State msg )
stopListeners =
    startStopListeners ErrorListenUnlisten SuccessListenUnlisten UnlistenType


startListeners : Platform.Router msg (Msg msg) -> ListenerDict msg -> State msg -> ( Task Never (), State msg )
startListeners =
    startStopListeners ErrorListenUnlisten SuccessListenUnlisten ListenType


addMySub : Platform.Router msg (Msg msg) -> State msg -> MySub msg -> ( ListenerDict msg, List (Task x ()) ) -> ( ListenerDict msg, List (Task x ()) )
addMySub router state sub ( dict, errorTasks ) =
    case sub of
        Listen errorTagger listenTagger eventTagger connectionId channel ->
            Dict.get connectionId dict
                |?> (\_ -> ( dict, Platform.sendToApp router (errorTagger ( connectionId, "Another listener exists" )) :: errorTasks ))
                ?= ( Dict.insert connectionId (ListenerState channel errorTagger listenTagger eventTagger) dict, errorTasks )


updateConnection : State msg -> ConnectionId -> Connection msg -> State msg
updateConnection state connectionId newConnection =
    { state | connections = Dict.insert connectionId newConnection state.connections }


settings0 : Platform.Router msg (Msg msg) -> (a -> Msg msg) -> Msg msg -> { onError : a -> Task msg (), onSuccess : Never -> Task x () }
settings0 router errorTagger tagger =
    { onError = \err -> Platform.sendToSelf router (errorTagger err)
    , onSuccess = \_ -> Platform.sendToSelf router tagger
    }


settings1 : Platform.Router msg (Msg msg) -> (a -> Msg msg) -> (b -> Msg msg) -> { onError : a -> Task Never (), onSuccess : b -> Task x () }
settings1 router errorTagger tagger =
    { onError = \err -> Platform.sendToSelf router (errorTagger err)
    , onSuccess = \result1 -> Platform.sendToSelf router (tagger result1)
    }


settings2 : Platform.Router msg (Msg msg) -> (a -> Msg msg) -> (b -> c -> Msg msg) -> { onError : a -> Task Never (), onSuccess : b -> c -> Task x () }
settings2 router errorTagger tagger =
    { onError = \err -> Platform.sendToSelf router (errorTagger err)
    , onSuccess = \result1 result2 -> Platform.sendToSelf router (tagger result1 result2)
    }


invalidConnectionId : Platform.Router msg (Msg msg) -> ErrorTagger msg -> ConnectionId -> Task Never ()
invalidConnectionId router errorTagger connectionId =
    Platform.sendToApp router <| errorTagger ( connectionId, "Invalid connectionId" )


handleCmd : Platform.Router msg (Msg msg) -> State msg -> MyCmd msg -> ( Task Never (), State msg )
handleCmd router state cmd =
    case cmd of
        Connect errorTagger tagger connectionLostTagger timeoutInSec host port_ database user password ->
            let
                connectionId =
                    state.nextId

                newConnection =
                    Connection connectionLostTagger tagger errorTagger Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

                connectionLostCb err =
                    Platform.sendToSelf router (ConnectionLost connectionId err)
            in
                ( Native.Postgres.connect (settings2 router (ErrorConnect connectionId) (SuccessConnect connectionId)) timeoutInSec host port_ database user password connectionLostCb
                , { state | nextId = state.nextId + 1, connections = Dict.insert connectionId newConnection state.connections }
                )

        Disconnect errorTagger tagger connectionId discardConnection ->
            (Dict.get connectionId state.connections)
                |?> (\connection ->
                        ( Native.Postgres.disconnect (settings0 router (ErrorDisconnect connectionId) (SuccessDisconnect connectionId)) connection.client discardConnection connection.nativeListener
                        , updateConnection state connectionId { connection | disconnectionTagger = Just tagger, errorTagger = errorTagger }
                        )
                            |> (\( disconnectTask, state ) ->
                                    (Dict.get connectionId state.listeners)
                                        |?> (\listenerState -> startStopListeners InternalErrorListenUnlisten (InternalSuccessUnlisten disconnectTask) UnlistenType router (Dict.insert connectionId listenerState Dict.empty) state)
                                        ?= ( disconnectTask, state )
                               )
                    )
                ?= ( invalidConnectionId router errorTagger connectionId, state )

        Query errorTagger tagger connectionId sql recordCount ->
            state.debug
                ?! ( \_ -> DebugF.log ("*** DEBUG:Postgres Query: ConnectionId:" +-+ connectionId) sql, always "" )
                |> always
                    (Maybe.map
                        (\connection ->
                            ( Native.Postgres.query (settings2 router (ErrorQuery connectionId sql) (SuccessQuery connectionId)) connection.client sql recordCount connection.nativeListener
                            , updateConnection state connectionId { connection | sql = Just sql, recordCount = Just recordCount, queryTagger = Just tagger, errorTagger = errorTagger }
                            )
                        )
                        (Dict.get connectionId state.connections)
                        ?= ( invalidConnectionId router errorTagger connectionId, state )
                    )

        MoreQueryResults errorTagger tagger connectionId ->
            Maybe.map
                (\connection ->
                    Maybe.map3
                        (\sql recordCount stream ->
                            ( Native.Postgres.moreQueryResults (settings2 router (ErrorQuery connectionId sql) (SuccessQuery connectionId)) connection.client stream recordCount
                            , updateConnection state connectionId { connection | queryTagger = Just tagger, errorTagger = errorTagger }
                            )
                        )
                        connection.sql
                        connection.recordCount
                        connection.stream
                        ?!= (\_ -> ( crashTask () <| "Invalid connection state: " ++ (toStringF <| printableConnection connection), state ))
                )
                (Dict.get connectionId state.connections)
                ?= ( invalidConnectionId router errorTagger connectionId, state )

        ExecuteSql errorTagger tagger connectionId sql ->
            Maybe.map
                (\connection ->
                    ( Native.Postgres.executeSql (settings1 router (ErrorExecuteSql connectionId sql) (SuccessExecuteSql connectionId)) connection.client sql
                    , updateConnection state connectionId { connection | sql = Just sql, executeTagger = Just tagger, errorTagger = errorTagger }
                    )
                )
                (Dict.get connectionId state.connections)
                ?= ( invalidConnectionId router errorTagger connectionId, state )

        ServerSideConfig errorTagger tagger maxPoolConnects ->
            ( Native.Postgres.serverSideConfig (settings0 router (ErrorServerSideConfig errorTagger) (SuccessServerSideConfig tagger)) maxPoolConnects
            , state
            )

        ClientSideConfig errorTagger tagger badResponseTagger wsUrl json ->
            ( Native.Postgres.clientSideConfig (settings0 router (ErrorClientSideConfig errorTagger) (SuccessClientSideConfig tagger)) router badResponseTagger wsUrl json
            , state
            )

        Debug debug ->
            Native.Postgres.setDebug debug
                |> (always ( Task.succeed (), { state | debug = debug } ))

        DumpState ->
            ( Platform.sendToSelf router InternalDumpState, state )


printableConnection : Connection msg -> Connection msg
printableConnection connection =
    { connection | client = Nothing, stream = Nothing }


printableState : State msg -> State msg
printableState state =
    { state | connections = Dict.map (\_ connection -> printableConnection connection) state.connections }


crashTask : a -> String -> Task Never a
crashTask x msg =
    let
        crash =
            Debug.crash msg
    in
        Task.succeed x


withConnection : State msg -> ConnectionId -> (Connection msg -> Task Never (State msg)) -> Bool -> String -> Task Never (State msg)
withConnection state connectionId f canOccurAfterDisconnect debugMsg =
    (Dict.get connectionId state.connections)
        |?> (\stateConnection -> f stateConnection)
        ?!= (\_ ->
                canOccurAfterDisconnect
                    ?! ( \_ -> Debug.log "Operation occurred after Disconnect" debugMsg |> (always <| Task.succeed state)
                       , \_ -> crashTask state <| "Connection Id: " ++ (toStringF connectionId) ++ " is not in state: " ++ (toStringF <| printableState state)
                       )
            )


withTagger : State msg -> Maybe tagger -> String -> (tagger -> Task Never (State msg)) -> Task Never (State msg)
withTagger state maybeTagger type_ f =
    case maybeTagger of
        Just tagger ->
            f tagger

        Nothing ->
            crashTask state <| "Missing " ++ type_ ++ " Tagger in state: " ++ (toStringF <| printableState state)


listenUnlistenToString : ListenUnlisten -> String
listenUnlistenToString type_ =
    case type_ of
        ListenType ->
            "listen"

        UnlistenType ->
            "unlisten"


debugSelfMsg : State msg -> Msg msg -> String
debugSelfMsg state selfMsg =
    state.debug
        ?! ( \_ ->
                (case selfMsg of
                    SuccessConnect connectionId client nativeListener ->
                        "SuccessConnect" +-+ ( connectionId, "<client>", "<nativeListener>" )

                    ErrorConnect connectionId err ->
                        "ErrorConnect" +-+ ( connectionId, err )

                    ConnectionLost connectionId err ->
                        "ConnectionLost" +-+ ( connectionId, err )

                    SuccessDisconnect connectionId ->
                        "SuccessDisconnect" +-+ connectionId

                    ErrorDisconnect connectionId err ->
                        "ErrorDisconnect" +-+ ( connectionId, err )

                    SuccessQuery connectionId stream results ->
                        "SuccessQuery" +-+ ( connectionId, "<stream>", results )

                    ErrorQuery connectionId sql err ->
                        "ErrorQuery" +-+ ( connectionId, sql, err )

                    SuccessExecuteSql connectionId result ->
                        "SuccessExecuteSql" +-+ ( connectionId, result )

                    ErrorExecuteSql connectionId sql err ->
                        "ErrorExecuteSql" +-+ ( connectionId, sql, err )

                    SuccessServerSideConfig tagger ->
                        "SuccessServerSideConfig" +-+ tagger

                    ErrorServerSideConfig errorTagger err ->
                        "ErrorServerSideConfig" +-+ ( errorTagger, err )

                    SuccessClientSideConfig tagger ->
                        "SuccessClientSideConfig" +-+ tagger

                    ErrorClientSideConfig errorTagger err ->
                        "ErrorClientSideConfig" +-+ ( errorTagger, err )

                    SuccessListenUnlisten channel type_ connectionId nativeListener ->
                        "SuccessListenUnlisten" +-+ ( channel, type_, connectionId, "<nativeListener>" )

                    ErrorListenUnlisten errorTagger channel type_ connectionId err ->
                        "ErrorListenUnlisten" +-+ ( errorTagger, channel, type_, connectionId, err )

                    InternalSuccessUnlisten disconnectTask channel type_ connectionId nativeListener ->
                        "InternalSuccessUnlisten" +-+ ( channel, type_, connectionId, "<nativeListener>" )

                    InternalErrorListenUnlisten errorTagger channel type_ connectionId err ->
                        "InternalErrorListenUnlisten" +-+ ( errorTagger, channel, type_, connectionId, err )

                    ListenEvent connectionId channel message ->
                        "ListenEvent" +-+ ( connectionId, channel, message )

                    InternalDumpState ->
                        "InternalDumpState " ++ (DebugF.toStringF <| printableState state)
                )
                    |> cleanElmString
                    |> DebugF.log "*** DEBUG:Postgres selfMsg"
           , always ""
           )


type Msg msg
    = SuccessConnect ConnectionId Client NativeListener
    | ErrorConnect ConnectionId String
    | ConnectionLost ConnectionId String
    | SuccessDisconnect ConnectionId
    | ErrorDisconnect ConnectionId String
    | SuccessQuery ConnectionId Stream (List String)
    | ErrorQuery ConnectionId Sql String
    | SuccessExecuteSql ConnectionId Int
    | ErrorExecuteSql ConnectionId Sql String
    | SuccessServerSideConfig (ConfigTagger msg)
    | ErrorServerSideConfig (ConfigErrorTagger msg) String
    | SuccessClientSideConfig (ConfigTagger msg)
    | ErrorClientSideConfig (ConfigErrorTagger msg) String
    | SuccessListenUnlisten ListenChannel ListenUnlisten ConnectionId NativeListener
    | ErrorListenUnlisten (ErrorTagger msg) ListenChannel ListenUnlisten ConnectionId String
    | ListenEvent ConnectionId String String
    | InternalErrorListenUnlisten (ErrorTagger msg) ListenChannel ListenUnlisten ConnectionId String
    | InternalSuccessUnlisten (Task Never ()) ListenChannel ListenUnlisten ConnectionId NativeListener
    | InternalDumpState


onSelfMsg : Platform.Router msg (Msg msg) -> Msg msg -> State msg -> Task Never (State msg)
onSelfMsg router selfMsg state =
    let
        sqlError connectionId sql err =
            let
                process connection =
                    Platform.sendToApp router (connection.errorTagger ( connectionId, err ++ "\n\nCommand:\n" ++ sql ))
                        &> Task.succeed state
            in
                withConnection state connectionId process False ""
    in
        debugSelfMsg state selfMsg
            |> always
                (case selfMsg of
                    SuccessConnect connectionId client nativeListener ->
                        let
                            process connection =
                                let
                                    newConnection =
                                        { connection | client = Just client, nativeListener = Just nativeListener }
                                in
                                    Platform.sendToApp router (newConnection.connectionTagger connectionId)
                                        &> Task.succeed { state | connections = Dict.insert connectionId newConnection state.connections }
                        in
                            withConnection state connectionId process False ""

                    ErrorConnect connectionId err ->
                        let
                            process connection =
                                Platform.sendToApp router (connection.errorTagger ( connectionId, err ))
                                    &> Task.succeed { state | connections = Dict.remove connectionId state.connections }
                        in
                            withConnection state connectionId process False ""

                    ConnectionLost connectionId err ->
                        let
                            process connection =
                                Platform.sendToApp router (connection.connectionLostTagger ( connectionId, err ))
                                    &> Task.succeed { state | connections = Dict.remove connectionId state.connections }
                        in
                            withConnection state connectionId process False ""

                    SuccessDisconnect connectionId ->
                        let
                            process connection =
                                let
                                    sendToApp tagger =
                                        Platform.sendToApp router (tagger connectionId)
                                            &> Task.succeed { state | connections = Dict.remove connectionId state.connections }
                                in
                                    withTagger state connection.disconnectionTagger "Disconnect" sendToApp
                        in
                            withConnection state connectionId process False ""

                    ErrorDisconnect connectionId err ->
                        let
                            process connection =
                                Platform.sendToApp router (connection.errorTagger ( connectionId, err ))
                                    &> Task.succeed state
                        in
                            withConnection state connectionId process False ""

                    SuccessQuery connectionId stream results ->
                        let
                            process connection =
                                let
                                    sendToApp tagger =
                                        Platform.sendToApp router (tagger ( connectionId, results ))
                                            &> Task.succeed { state | connections = Dict.insert connectionId { connection | stream = Just stream } state.connections }
                                in
                                    withTagger state connection.queryTagger "Query" sendToApp
                        in
                            withConnection state connectionId process False ""

                    ErrorQuery connectionId sql err ->
                        sqlError connectionId sql err

                    SuccessExecuteSql connectionId result ->
                        let
                            process connection =
                                let
                                    sendToApp tagger =
                                        Platform.sendToApp router (tagger ( connectionId, result ))
                                            &> Task.succeed state
                                in
                                    withTagger state connection.executeTagger "Execute" sendToApp
                        in
                            withConnection state connectionId process False ""

                    ErrorExecuteSql connectionId sql err ->
                        sqlError connectionId sql err

                    SuccessServerSideConfig tagger ->
                        Platform.sendToApp router (tagger ())
                            &> Task.succeed state

                    ErrorServerSideConfig errorTagger err ->
                        Platform.sendToApp router (errorTagger err)
                            &> Task.succeed state

                    SuccessClientSideConfig tagger ->
                        Platform.sendToApp router (tagger ())
                            &> Task.succeed state

                    ErrorClientSideConfig errorTagger err ->
                        Platform.sendToApp router (errorTagger err)
                            &> Task.succeed state

                    SuccessListenUnlisten channel type_ connectionId nativeListener ->
                        let
                            process connection =
                                let
                                    newState =
                                        case type_ of
                                            ListenType ->
                                                { state | nativeListeners = Dict.insert connectionId nativeListener state.nativeListeners }

                                            UnlistenType ->
                                                { state | nativeListeners = Dict.remove connectionId state.nativeListeners }

                                    sendToApp tagger =
                                        Platform.sendToApp router (tagger ( connectionId, channel, type_ ))
                                            &> Task.succeed newState
                                in
                                    withTagger state connection.listenTagger "ListenUnlisten" sendToApp
                        in
                            withConnection state connectionId process (type_ == UnlistenType) ("SuccessListenUnlisten for: " ++ (toString type_))

                    ErrorListenUnlisten errorTagger channel type_ connectionId err ->
                        Platform.sendToApp router (errorTagger ( connectionId, "Operation: " ++ listenUnlistenToString type_ ++ ", Channel: " ++ channel ++ ", Error: " ++ err ))
                            &> Task.succeed state

                    InternalSuccessUnlisten disconnectTask channel type_ connectionId nativeListener ->
                        disconnectTask &> Task.succeed { state | nativeListeners = Dict.remove connectionId state.nativeListeners }

                    InternalErrorListenUnlisten errorTagger channel type_ connectionId err ->
                        onSelfMsg router (ErrorDisconnect connectionId ("Unable to disconnect due to Unlisten Error on channel: " ++ channel ++ " for connectionId: " ++ (toString connectionId) ++ " Error: " ++ err)) state

                    ListenEvent connectionId channel message ->
                        let
                            process connection =
                                let
                                    sendToApp tagger =
                                        Platform.sendToApp router (tagger ( connectionId, channel, message ))
                                            &> Task.succeed state
                                in
                                    withTagger state connection.eventTagger "ListenEvent" sendToApp
                        in
                            withConnection state connectionId process True "ListenEvent"

                    InternalDumpState ->
                        Task.succeed state
                )
