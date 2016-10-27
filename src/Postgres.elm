effect module Postgres
    where { command = MyCmd, subscription = MySub }
    exposing
        ( connect
        , disconnect
        , query
        , moreQueryResults
        , executeSql
        , clientSideConfig
        , listen
        , ConnectionId
        , ListenChannel
        , Sql
        , WSUrl
        , ListenUnlisten(..)
        )

{-| Postgres Effects Manager to access Postgres DBs

The native driver is https://github.com/brianc/node-postgres.

# Commands
@docs connect, disconnect, query, moreQueryResults, executeSql, clientSideConfig

# Subscriptions
@docs listen

# Types
@docs ConnectionId, ListenChannel, Sql, WSUrl, ListenUnlisten
-}

import Task exposing (Task)
import Dict exposing (Dict)
import DebugF exposing (toStringF)
import Native.Postgres


-- API


type MyCmd msg
    = Connect (ErrorTagger msg) (ConnectTagger msg) (ConnectionLostTagger msg) TimeoutInSec String Int String String String
    | Disconnect (ErrorTagger msg) (DisconnectTagger msg) ConnectionId Bool
    | Query (ErrorTagger msg) (QueryTagger msg) ConnectionId Sql Int
    | MoreQueryResults (ErrorTagger msg) (QueryTagger msg) ConnectionId
    | ExecuteSql (ErrorTagger msg) (ExecuteTagger msg) ConnectionId Sql
    | ClientSideConfig (ConfigErrorTagger msg) (ConfigTagger msg) (BadResponseTagger msg) (Maybe WSUrl) (Maybe JsonString)


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


type alias ErrorTagger msg =
    ( ConnectionId, String ) -> msg


type alias ConnectTagger msg =
    ConnectionId -> msg


type alias ConnectionLostTagger msg =
    ( ConnectionId, String ) -> msg


type alias DisconnectTagger msg =
    ConnectionId -> msg


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
    }



-- Operators


(?=) : Maybe a -> a -> a
(?=) =
    flip Maybe.withDefault


{-| lazy version of ?= operator
-}
(?!=) : Maybe a -> (() -> a) -> a
(?!=) maybe lazy =
    case maybe of
        Just x ->
            x

        Nothing ->
            lazy ()


(|?>) : Maybe a -> (a -> b) -> Maybe b
(|?>) =
    flip Maybe.map


(&>) : Task x a -> Task x b -> Task x b
(&>) t1 t2 =
    t1 `Task.andThen` \_ -> t2


(&>>) : Task x a -> (a -> Task x b) -> Task x b
(&>>) t1 f =
    t1 `Task.andThen` f



-- Init


init : Task Never (State msg)
init =
    Task.succeed (State 0 Dict.empty Dict.empty Dict.empty)



-- Cmds


cmdMap : (a -> b) -> MyCmd a -> MyCmd b
cmdMap f cmd =
    case cmd of
        Connect errorTagger tagger connectionLostTagger timeoutInSec host port' database user password ->
            Connect (f << errorTagger) (f << tagger) (f << connectionLostTagger) timeoutInSec host port' database user password

        Disconnect errorTagger tagger client discardConnection ->
            Disconnect (f << errorTagger) (f << tagger) client discardConnection

        Query errorTagger tagger connectionId sql recordCount ->
            Query (f << errorTagger) (f << tagger) connectionId sql recordCount

        MoreQueryResults errorTagger tagger connectionId ->
            MoreQueryResults (f << errorTagger) (f << tagger) connectionId

        ExecuteSql errorTagger tagger connectionId sql ->
            ExecuteSql (f << errorTagger) (f << tagger) connectionId sql

        ClientSideConfig errorTagger tagger badResponseTagger wsUrl json ->
            ClientSideConfig (f << errorTagger) (f << tagger) (f << badResponseTagger) wsUrl json



-- commands


{-| Connect to a database

    Usage:
        connect ErrorConnect SuccessConnect ConnectionLost 15 myHost 5432 myDb userName password

    where:
        ErrorConnect, SuccessConnect and ConnectionLost are your application's messages to handle the different scenarios
-}
connect : ErrorTagger msg -> ConnectTagger msg -> ConnectionLostTagger msg -> TimeoutInSec -> String -> Int -> String -> String -> String -> Cmd msg
connect errorTagger tagger connectionLostTagger timeoutInSec host port' database user password =
    command (Connect errorTagger tagger connectionLostTagger timeoutInSec host port' database user password)


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



-- subscription taggers


{-| (connectionId, channel, type) where type = "listen" or "unlisten"
-}
type alias ListenTagger msg =
    ( ConnectionId, ListenChannel, ListenUnlisten ) -> msg


{-| (connectionId, channel, message)
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
onEffects router cmds newSubs state =
    let
        newSubsDict =
            List.foldl addMySub Dict.empty newSubs

        oldListeners =
            Dict.diff state.listeners newSubsDict

        newListeners =
            Dict.diff newSubsDict state.listeners

        keepListeners =
            Dict.intersect state.listeners newSubsDict

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
            stopListeners router oldListeners cmdState

        ( startTask, startState ) =
            startListeners router newListeners stopState
    in
        cmdTask
            &> stopTask
            &> startTask
            &> Task.succeed { startState | listeners = Dict.union keepListeners newListeners }


startStopListeners : ListenUnlisten -> Platform.Router msg (Msg msg) -> ListenerDict msg -> State msg -> ( Task Never (), State msg )
startStopListeners listenUnlisten router listeners state =
    let
        startStopListener connectionId listenerState ( task, state ) =
            let
                ( executeTask, executeState ) =
                    let
                        nativeListener =
                            Dict.get connectionId state.nativeListeners

                        errorTaggerCtor =
                            ErrorListenUnlisten listenerState.errorTagger listenerState.channel listenUnlisten connectionId

                        getTask connection type' =
                            let
                                settings =
                                    (settings1 router
                                        errorTaggerCtor
                                        (SuccessListenUnlisten listenerState.channel type' connectionId)
                                    )
                            in
                                case type' of
                                    ListenType ->
                                        Native.Postgres.listen settings connection.client listenerState.channel (Platform.sendToSelf router << ListenEvent connectionId listenerState.channel)

                                    UnlistenType ->
                                        Native.Postgres.unlisten settings connection.client listenerState.channel nativeListener

                        maybeTask =
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
                    in
                        maybeTask
                            ?= ( Platform.sendToSelf router <| errorTaggerCtor "Invalid connectionId", state )

                -- ?= ( invalidConnectionId router listenerState.errorTagger connectionId, state )
            in
                ( executeTask &> task, executeState )
    in
        Dict.foldl startStopListener ( Task.succeed (), state ) listeners


stopListeners : Platform.Router msg (Msg msg) -> ListenerDict msg -> State msg -> ( Task Never (), State msg )
stopListeners =
    startStopListeners UnlistenType


startListeners : Platform.Router msg (Msg msg) -> ListenerDict msg -> State msg -> ( Task Never (), State msg )
startListeners =
    startStopListeners ListenType


addMySub : MySub msg -> ListenerDict msg -> ListenerDict msg
addMySub sub dict =
    case sub of
        Listen errorTagger listenTagger eventTagger connectionId channel ->
            Dict.insert connectionId (ListenerState channel errorTagger listenTagger eventTagger) dict


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
        Connect errorTagger tagger connectionLostTagger timeoutInSec host port' database user password ->
            let
                connectionId =
                    state.nextId

                newConnection =
                    Connection connectionLostTagger tagger errorTagger Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

                connectionLostCb err =
                    Platform.sendToSelf router (ConnectionLost connectionId err)
            in
                ( Native.Postgres.connect (settings2 router (ErrorConnect connectionId) (SuccessConnect connectionId)) timeoutInSec host port' database user password connectionLostCb
                , { state | nextId = state.nextId + 1, connections = Dict.insert connectionId newConnection state.connections }
                )

        Disconnect errorTagger tagger connectionId discardConnection ->
            Maybe.map
                (\connection ->
                    ( Native.Postgres.disconnect (settings0 router (ErrorDisconnect connectionId) (SuccessDisconnect connectionId)) connection.client discardConnection connection.nativeListener
                    , updateConnection state connectionId { connection | disconnectionTagger = Just tagger, errorTagger = errorTagger }
                    )
                )
                (Dict.get connectionId state.connections)
                ?= ( invalidConnectionId router errorTagger connectionId, state )

        Query errorTagger tagger connectionId sql recordCount ->
            Maybe.map
                (\connection ->
                    ( Native.Postgres.query (settings2 router (ErrorQuery connectionId sql) (SuccessQuery connectionId)) connection.client sql recordCount connection.nativeListener
                    , updateConnection state connectionId { connection | sql = Just sql, recordCount = Just recordCount, queryTagger = Just tagger, errorTagger = errorTagger }
                    )
                )
                (Dict.get connectionId state.connections)
                ?= ( invalidConnectionId router errorTagger connectionId, state )

        MoreQueryResults errorTagger tagger connectionId ->
            Maybe.map
                (\connection ->
                    Maybe.map3
                        (\sql recordCount stream ->
                            ( Native.Postgres.moreQueryResults (settings2 router (ErrorQuery connectionId sql) (SuccessQuery connectionId)) connection.client stream recordCount
                            , state
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

        ClientSideConfig errorTagger tagger badResponseTagger wsUrl json ->
            ( Native.Postgres.clientSideConfig (settings0 router (ErrorClientSideConfig errorTagger) (SuccessClientSideConfig tagger)) router badResponseTagger wsUrl json
            , state
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
    | SuccessClientSideConfig (ConfigTagger msg)
    | ErrorClientSideConfig (ConfigErrorTagger msg) String
    | SuccessListenUnlisten ListenChannel ListenUnlisten ConnectionId NativeListener
    | ErrorListenUnlisten (ErrorTagger msg) ListenChannel ListenUnlisten ConnectionId String
    | ListenEvent ConnectionId String String


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


withConnection : State msg -> ConnectionId -> (Connection msg -> Task Never (State msg)) -> Task Never (State msg)
withConnection state connectionId f =
    let
        stateConnection =
            Dict.get connectionId state.connections
    in
        case stateConnection of
            Just stateConnection ->
                f stateConnection

            Nothing ->
                crashTask state <| "Connection Id: " ++ (toStringF connectionId) ++ " is not in state: " ++ (toStringF <| printableState state)


withTagger : State msg -> Maybe tagger -> String -> (tagger -> Task Never (State msg)) -> Task Never (State msg)
withTagger state maybeTagger type' f =
    case maybeTagger of
        Just tagger ->
            f tagger

        Nothing ->
            crashTask state <| "Missing " ++ type' ++ " Tagger in state: " ++ (toStringF <| printableState state)


listenUnlistenToString : ListenUnlisten -> String
listenUnlistenToString type' =
    case type' of
        ListenType ->
            "listen"

        UnlistenType ->
            "unlisten"


onSelfMsg : Platform.Router msg (Msg msg) -> Msg msg -> State msg -> Task Never (State msg)
onSelfMsg router selfMsg state =
    let
        sqlError connectionId sql err =
            let
                process connection =
                    Platform.sendToApp router (connection.errorTagger ( connectionId, err ++ "\n\nCommand:\n" ++ sql ))
                        &> Task.succeed state
            in
                withConnection state connectionId process
    in
        case selfMsg of
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
                    withConnection state connectionId process

            ErrorConnect connectionId err ->
                let
                    process connection =
                        Platform.sendToApp router (connection.errorTagger ( connectionId, err ))
                            &> Task.succeed { state | connections = Dict.remove connectionId state.connections }
                in
                    withConnection state connectionId process

            ConnectionLost connectionId err ->
                let
                    process connection =
                        Platform.sendToApp router (connection.connectionLostTagger ( connectionId, err ))
                            &> Task.succeed { state | connections = Dict.remove connectionId state.connections }
                in
                    withConnection state connectionId process

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
                    withConnection state connectionId process

            ErrorDisconnect connectionId err ->
                let
                    process connection =
                        Platform.sendToApp router (connection.errorTagger ( connectionId, err ))
                            &> Task.succeed state
                in
                    withConnection state connectionId process

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
                    withConnection state connectionId process

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
                    withConnection state connectionId process

            ErrorExecuteSql connectionId sql err ->
                sqlError connectionId sql err

            SuccessClientSideConfig tagger ->
                Platform.sendToApp router (tagger ())
                    &> Task.succeed state

            ErrorClientSideConfig errorTagger err ->
                Platform.sendToApp router (errorTagger err)
                    &> Task.succeed state

            SuccessListenUnlisten channel type' connectionId nativeListener ->
                let
                    newListener =
                        (Maybe.map (\listenerState -> listenerState) (Dict.get connectionId state.listeners))

                    process connection =
                        let
                            newState =
                                case type' of
                                    ListenType ->
                                        { state | nativeListeners = Dict.insert connectionId nativeListener state.nativeListeners }

                                    UnlistenType ->
                                        state

                            sendToApp tagger =
                                Platform.sendToApp router (tagger ( connectionId, channel, type' ))
                                    &> Task.succeed newState
                        in
                            withTagger state connection.listenTagger "ListenUnlisten" sendToApp
                in
                    withConnection state connectionId process

            ErrorListenUnlisten errorTagger channel type' connectionId err ->
                Platform.sendToApp router (errorTagger ( connectionId, "Operation: " ++ listenUnlistenToString type' ++ ", Channel: " ++ channel ++ ", Error: " ++ err ))
                    &> Task.succeed state

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
                    withConnection state connectionId process
