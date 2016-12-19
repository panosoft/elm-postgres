# Postgres Effects Manager for Elm

> Effects Manager for Node-based Elm programs to be able to access Postgres SQL databases.

> This Effects Manager also works on the client side since the native code is environment aware. The native client code will delegate to an Authenticating Proxy Server which is also written in Elm and use this Effects Manager with the server native code.

> It is called [PGProxy](https://github.com/panosoft/elm-pgproxy).

> The module Proxy.Decoder has the JSON Decoders for handling the messages sent by the native client code. This module is used in PGProxy.

> It is possible to write your own PGProxy, but I'd suggest you first look to PGProxy as a reference implementation. Hopefully, it will fit your needs.

This Effects Manager is built on top of the canonical PG library for node, [node-postgres](https://github.com/brianc/node-postgres).

## Install

### Elm

Since the Elm Package Manager doesn't allow for Native code and this uses Native code, you have to install it directly from GitHub, e.g. via [elm-github-install](https://github.com/gdotdesign/elm-github-install) or some equivalent mechanism.

### Node modules

You also need to install the dependent node modules at the root of your Application Directory. See the example `package.json` for a list of the dependencies.

The installation can be done via `npm install` command.

## API

### Commands

> Connect to a database

This must be done before any other commands are run. The connection may come from a pool of connections unless it was discarded when it was disconnected.

Connections are maintained by the Effect Manager State and are referenced via `connectionId`s.

```elm
connect : ErrorTagger msg -> ConnectTagger msg -> ConnectionLostTagger msg -> String -> Int -> String -> String -> String -> Cmd msg
connect errorTagger tagger connectionLostTagger host port' database user password
```
__Usage__

```elm
connect ErrorConnect SuccessConnect ConnectionLost myHost 5432 myDb userName password
```
* `ErrorConnect`, `SuccessConnect` and `ConnectionLost` are your application's messages to handle the different scenarios.
* `myHost` is the host name of the Postgres server
* `5432` is the port to communicate to the Postgres server
* `myDb` is the name of the database to connect
* `userName` and `password` are the logon credentials for Postgres server (these are required and cannot be blank)

> Disconnect from database

When a connection is no longer needed, it can be disconnected. It will be placed back into the pool unless `discardConnection` is `True`.

```elm
disconnect : ErrorTagger msg -> DisconnectTagger msg -> ConnectionId -> Bool -> Cmd msg
disconnect errorTagger tagger connectionId discardConnection
```
__Usage__

```elm
disconnect ErrorDisconnect SuccessDisconnect 123 False
```

* `ErrorDisconnect` and `SuccessDisconnect` are your application's messages to handle the different scenarios
* `123` is the connection id from the `(ConnectTagger msg)` handler
* `False` means do NOT discard the connection, i.e. return it into the pool

> Query the database

This runs any SQL command that returns a SINGLE result set, usually a `SELECT` statement. The result set is a List of JSON-formatted Strings where each object has keys that match the column names.

```elm
query : ErrorTagger msg -> QueryTagger msg -> ConnectionId -> Sql -> Int -> Cmd msg
query errorTagger tagger connectionId sql recordCount
```
__Usage__

```elm
query ErrorQuery SuccessQuery 123 "SELECT * FROM table" 1000
```
* `ErrorQuery` and `SuccessQuery` are your application's messages to handle the different scenarios
* `123` is the connection id from the `(ConnectTagger msg)` handler
* `"SELECT * FROM table"` is the SQL Command that returns a SINGLE result set
* `1000` is the maximum number of records or rows to return in this call and subsequent `Postgres.moreQueryResults` calls
	* If the number of records returned is less than this amount then there are no more records

> Get more records from the database

This continues retrieving records from the last `Postgres.query` call. It will retrieve at most the number of records originally specified by the `recordCount` parameter of that call.

```elm
moreQueryResults : ErrorTagger msg -> QueryTagger msg -> ConnectionId -> Cmd msg
moreQueryResults errorTagger tagger connectionId
```
__Usage__

```elm
moreQueryResults ErrorQuery SuccessQuery 123
```
* `ErrorQuery` and `SuccessQuery` are your application's messages to handle the different scenarios:
	* When `(snd SuccessQuery) == []` then there are no more records
* `123` is the connection id from the `(ConnectTagger msg)` handler

> Execute SQL command

This will execute a SQL command that returns a COUNT, e.g. INSERT, UPDATE, DELETE, etc.

```elm
executeSql : ErrorTagger msg -> ExecuteTagger msg -> ConnectionId -> Sql -> Cmd msg
executeSql errorTagger tagger connectionId sql
```
__Usage__

```elm
executeSql ErrorExecuteSql SuccessExecuteSql 123 "DELETE FROM table"
```
* `ErrorExecuteSql` and `SuccessExecuteSql` are your application's messages to handle the different scenarios
* `123` is the connection id from the (ConnectTagger msg) handler
* `"DELETE FROM table"` is the SQL Command that returns a ROW COUNT

> Client side configuration

This is an extra step when using this Effects Manager on the client. It must be the FIRST call so that the native client
code will delegate properly to a proxy server, e.g. [elm-pgproxy](https://github.com/panosoft/elm-pgproxy).

The first time this is called, `url` MUST be provided. Subsequent calls can pass Nothing and the previous URL will be used.

This is useful when making changes ONLY to the JSON object when the authentication credentials change and the proxy server authenticates.

```elm
clientSideConfig : ConfigErrorTagger msg -> ConfigTagger msg -> BadResponseTagger msg -> Maybe WSUrl -> Maybe JsonString -> Cmd msg
clientSideConfig errorTagger tagger badResponseTagger url json

```
__Usage__

```elm
clientSideConfig ConfigError Configured BadResponse (Just "ws://pg-proxy-server") (Just "{\"sessionId\": \"1f137f5f-43ec-4393-b5e8-bf195015e697\"}")
```
* `ConfigError`, `Configured` and `BadResponse` are your application's messages to handle the different scenarios
* `ws:/pg-proxy-server` is the URL to the Websocket for the PG Proxy (all new connections will use this URL)
* `{\"sessionId\": \"1f137f5f-43ec-4393-b5e8-bf195015e697\"}` is the JSON string of an object to be merged with all requests

Here, in this example, the JSON string to merge is used by the Proxy Server to authenticate the request. The protocol with the proxy doesn't require this. It's implemenation specific.

[PGProxy](https://github.com/panosoft/elm-pgproxy) delegates authentication to the application allowing for flexible authentication.

N.B. connecting to the Database should NOT be done until the `Configured` message has been received. That's because the trasport between the client and the proxy is Websockets.

### Subscriptions

> Subscribe to Postgres NOTIFY messages

Subscribe to a Postgres PubSub Channel.

For more about Postgres notification, see [NOTIFY](https://www.postgresql.org/docs/current/static/sql-notify.html) and [LISTEN](https://www.postgresql.org/docs/current/static/sql-listen.html).

```elm
listen : ErrorTagger msg -> ListenTagger msg -> ListenEventTagger msg -> Int -> String -> Sub msg
listen errorTagger listenTagger eventTagger connectionId channel
```
__Usage__

```elm
listen ErrorListenUnlisten SuccessListenUnlisten ListenEvent 123 "myChannel"
```
* `ErrorListenUnlisten`,  `SuccessListenUnlisten` and `ListenEvent` are your application's messages to handle the different scenarios
	* Messages are sent to the application upon subscribe and unsubscribe (Listen and Unlisten)
* `123` is the connection id from the (ConnectTagger msg) handler
* `"myChannel"` is the name of the Channel that will publish a STRING payload

### Messages

#### ErrorTagger

All error messages are of this type.

```elm
type alias ErrorTagger msg =
	( ConnectionId, String ) -> msg
```

__Usage__

```elm
ConnectError ( connectionId, errorMessage ) ->
	let
		l =
			Debug.log "ConnectError" ( connectionId, errorMessage )
	in
		model ! []
```

#### ConnectTagger

Successful connection.

```elm
type alias ConnectTagger msg =
	ConnectionId -> msg
```

__Usage__

```elm
Connect connectionId ->
	let
		l =
			Debug.log "Connect" connectionId
	in
		model ! []
```

#### ConnectLostTagger

Connection has been lost.

```elm
type alias ConnectionLostTagger msg =
	( ConnectionId, String ) -> msg
```

__Usage__

```elm
ConnectLostError ( connectionId, errorMessage ) ->
	let
		l =
			Debug.log "ConnectLostError" ( connectionId, errorMessage )
	in
		model ! []
```

#### DisconnectTagger

Successful disconnect.

```elm
type alias DisconnectTagger msg =
	ConnectionId -> msg
```

__Usage__

```elm
Disconnect connectionId ->
	let
		l =
			Debug.log "Disconnect" connectionId
	in
		model ! []
```

#### QueryTagger

Successful Query and the first `recordCount` records.

```elm
type alias QueryTagger msg =
	( ConnectionId, List String ) -> msg
```

__Usage__

```elm
RowsReceived ( connectionId, rowStrs ) ->
	let
		l =
			Debug.log "RowsReceived" ( connectionId, rowStrs )
	in
		model ! []
```

#### ExecuteTagger

Successful SQL command execution.

```elm
type alias ExecuteTagger msg =
	( ConnectionId, Int ) -> msg
```

__Usage__

```elm
ExecuteComplete ( connectionId, count ) ->
	let
		l =
			Debug.log "ExecuteComplete" ( connectionId, count )
	in
		model ! []
```

#### ListenTagger

Successful listen or unlisten.

```elm
type alias ListenTagger msg =
	( ConnectionId, ListenChannel, ListenUnlisten ) -> msg
```

__Usage__

```elm
ListenUnlisten ( connectionId, channel, type_ ) ->
	let
		l =
			case type_ of
				ListenType ->
					Debug.log "Listen" ( connectionId, channel )

				UnlistenType ->
					Debug.log "Unlisten" ( connectionId, channel )
	in
		model ! []
```

#### ListenEventTagger

Listen event.

```elm
type alias ListenEventTagger msg =
    ( ConnectionId, ListenChannel, String ) -> msg
```

__Usage__

```elm
ListenEvent ( connectionId, channel, message ) ->
	let
		l =
			Debug.log "ListenEvent" ( connectionId, channel, message )
	in
		model ! []
```
#### ConfigTagger

Configured event.

```elm
type alias ConfigTagger msg =
    () -> msg
```

__Usage__

```elm
Configured () ->
	let
		l =
			Debug.log "Configured" ""
	in
		model ! [ Postgres.connect ErrorConnect SuccessConnect ConnectionLost myHost 5432 myDb userName password ]
```

## Warning

This library is still in alpha.
