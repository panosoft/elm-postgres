# Postgres Effects Manager for Elm

> Effects Manager for Node-based Elm programs to be able to access Postgres SQL databases.

> This Effects Manager also works on the client side since the native code is environment aware. The native client code will delegate to an Authenticating Proxy Server which is also written in Elm and use this Effects Manager with the server native code.

> It is called [PGProxy](https://github.com/panosoft/elm-pgproxy).

> The module Proxy.Decoder has the JSON Decoders for handling the messages sent by the native client code. This module is used in PGProxy.

> It is possible to write your own PGProxy using it as a reference implementation, but I'd suggest you first look to PGProxy. Hopefully, it will fit your needs.

This Effects Manager is built on top of the canonical PG library for node, [node-postgres](https://github.com/brianc/node-postgres).

## Install

### Elm

Since the Elm Package Manager doesn't allow for Native code and this uses Native code, you have to install it directly from GitHub, e.g. via [elm-github-install](https://github.com/gdotdesign/elm-github-install) or some equivalent mechanism.

### Node modules

You also need to install the dependent node modules at the root of your Application Directory. See the example `package.json` for a list of the dependencies.

The installation can be done via `npm install` command.

## Server side usage

All of the following API calls can be used on the server side except for `clientSideConfig` which is only useful when using this module on the client side.

## Client side Usage (Browser & Electron)

To use this Effects Manager on the client side, a Proxy server, e.g. [PGProxy](https://github.com/panosoft/elm-pgproxy), must be used. This server will make the actual calls to the Postgres DB on the server side.

You can determine whether you're running on a client or server by calling `isOnClient`.

The `clientSideConfig` must be used to configure this module for communication to a backend proxy.

`clientSideConfig` must be the first call before any other API calls are made.

`PGProxy` can be used as is or as a reference implementation for building your own proxy. Since it's an authenticating proxy, extra authentication information can be automatically added to all calls between this module and `PGProxy` via the `clientSideConfig` call. This autentication information is implementation specific.

Since client side configuration is **global** to the module there may only be one connection to a single proxy server. This should not prove limiting in most scenarios.

The native code of this module relies on the global definition of `process.env.BROWSER` to be `truthy` for this module to work in client mode. This can be done via `webpack` easily by using the plugin `webpack.DefinePlugin` to define the global process variable as shown in this example `webpack.config.json`:

```js
const webpack = require('/usr/local/lib/node_modules/webpack');

module.exports = {
    entry: './Client/index.js',
    output: {
        path: './build',
        filename: 'index.js'
    },
    plugins: [
        new webpack.DefinePlugin({
            "process.env": {
                BROWSER: JSON.stringify(true)
            }
        })
    ],
    module: {
        loaders: [
            {
                test: /\.html$/,
                exclude: /node_modules/,
                loader: 'html-loader'
            },
            {
                test: /\.elm$/,
                exclude: [/elm-stuff/],
                loader: 'elm-webpack'
            }
        ]
    }
};
```
`process.env.BROWSER` must be defined in this way so `webpack` will ignore the `require`s in the server portion of the native code since those libraries won't exist for the client build.

Note that this uses the [Elm Webpack Loader](https://github.com/elm-community/elm-webpack-loader) and [HTML Webpack Loader](https://github.com/webpack/html-loader).

This can be found in the client's `node_modules` under the `devDependencies` key as shown in this example `package.json`:

```json
{
  "name": "test-postgres-proxy",
  "version": "1.0.0",
  "description": "Client and server for testing client proxy part of the PostGres Effect Manager",
  "author": "Charles Scalfani",
  "license": "Unlicense",
  "dependencies": {
    "@panosoft/elm-native-helpers": "^0.1.9",
	"ws": "^1.1.1"
  },
  "devDependencies": {
    "elm-webpack-loader": "^3.0.6",
    "html-loader": "^0.4.4"
  }
}
```

The client that uses this webpack config is built with this command:

```bash
webpack --config Client/webpack.config.js --display-error-details
```

`process.env.CLIENT` can be set if you're running this Effects Manager from Node and you want to run as a client, e.g. in [Electron](https://github.com/electron/electron). This can easily be set via the command line when launching the Node application:

```bash
CLIENT=true node main
```

 or it can be hardcoded in the main.js:


```js
// compile with:
//		elm make Test/App.elm --output elm.js

// tell Postgres to use PGProxy
process.env.CLIENT = true;

// load Elm module
const elm = require('./elm.js');

// get Elm ports
const ports = elm.App.worker().ports;

// keep our app alive until we get an exitCode from Elm or SIGINT or SIGTERM (see below)
setInterval(id => id, 86400);

ports.exitApp.subscribe(exitCode => {
	console.log('Exit code from Elm:', exitCode);
	process.exit(exitCode);
});

process.on('uncaughtException', err => {
	console.log(`Uncaught exception:\n`, err);
	process.exit(1);
});

process.on('SIGINT', _ => {
	console.log(`SIGINT received.`);
	ports.externalStop.send(null);
});

process.on('SIGTERM', _ => {
	console.log(`SIGTERM received.`);
	ports.externalStop.send(null);
});
```


## Proxy protocol

### Marshalling Function Calls

Each API call (except for `clientSideConfig`) will build a JSON object of the following format:

```js
{
	"func": "api-function-name",
	// remaining keys are parameters
}
```

For example, the Postgres Effects Manager Command, `query` has the following signature:

```elm
query : ErrorTagger msg -> QueryTagger msg -> ConnectionId -> Sql -> Int -> Cmd msg
query errorTagger tagger connectionId sql recordCount
```

The parameters that need to be marshalled to the Proxy are `sql` and `recordCount`. Therefore the JSON object that's sent to the Proxy has the following format:

```js
{
	"func": "query",
	"sql": "SELECT * FROM tbl",
	"recordCount": 100
}
```

### Authenticating Proxy Support

To support Authenticating Proxies, `clientSideConfig` takes an additional JSON string parameter that will be merged with the JSON objects that represent function calls. For example, if the following configuration call was made:

```elm
clientSideConfig ConfigError Configured BadResponse (Just "ws://pg-proxy-server") (Just "{\"sessionId\": \"1f137f5f-43ec-4393-b5e8-bf195015e697\"}")
```

then the previous JSON object would be transformed into:

```js
{
	"sessionId": "1f137f5f-43ec-4393-b5e8-bf195015e697",
	"func": "query",
	"sql": "SELECT * FROM tbl",
	"recordCount": 100
}
```

before being sent to the Authenticating Proxy. In the case of [PGProxy](https://github.com/panosoft/elm-pgproxy), it passes the *entire* JSON object to the authenticator. That authenticator is provided by the server that houses the PGProxy service.

If the authenticating credentials, e.g. `sessionId`, were to change during the execution of the client side program, then another call to `clientSideConfig` must be made to set the new credentials, e.g.:

```elm
clientSideConfig ConfigError Configured BadResponse Nothing (Just "{\"sessionId\": \"1f137f5f-43ec-4393-b5e8-bf195015e697\"}")
```
Note that we didn't have to set the websocket address. The use of Nothing here will NOT change the old value.


### Request/Response Ids

Each request is given a unique id to help correlate client and server side log messages. In the case of [PGProxy](https://github.com/panosoft/elm-pgproxy), it responds with the same id as was in the original request.

So our final request looks like:

```js
{
	"sessionId": "1f137f5f-43ec-4393-b5e8-bf195015e697",
	"requestId": 43,
	"func": "query",
	"sql": "SELECT * FROM tbl",
	"recordCount": 100
}
```

### Proxy Responses

Proxy Responses are JSON and of the format for successful responses:

```js
{
	"success": true,
	// the rest of the keys for the Service's response
}
```

And for non-successful responses:

```js
{
	"success": false,
	"error": "Error message"
}
```

In the case of `PGProxy`, these responses will also have `requestId` keys that echo the values sent by the request.

## API

### Helpers

> Check to see if we're running on the client, i.e. using PGProxy (or something like it)

```elm
isOnClient : Bool
isOnClient
```


### Commands

> Connect to a database

This must be done before any other commands are run. The connection may come from a pool of connections unless it was discarded when it was disconnected.

Connections are maintained by the Effect Manager State and are referenced via `connectionId`s.

```elm
connect : ErrorTagger msg -> ConnectTagger msg -> ConnectionLostTagger msg -> String -> Int -> String -> String -> String -> Cmd msg
connect errorTagger tagger connectionLostTagger host port_ database user password
```
__Usage__

```elm
Postgres.connect ErrorConnect SuccessConnect ConnectionLost myHost 5432 myDb userName password
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
Postgres.disconnect ErrorDisconnect SuccessDisconnect 123 False
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
Postgres.query ErrorQuery SuccessQuery 123 "SELECT * FROM table" 1000
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
Postgres.moreQueryResults ErrorQuery SuccessQuery 123
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
Postgres.executeSql ErrorExecuteSql SuccessExecuteSql 123 "DELETE FROM table"
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
Postgres.clientSideConfig ConfigError Configured BadResponse (Just "ws://pg-proxy-server") (Just "{\"sessionId\": \"1f137f5f-43ec-4393-b5e8-bf195015e697\"}")
```
* `ConfigError`, `Configured` and `BadResponse` are your application's messages to handle the different scenarios
* `ws:/pg-proxy-server` is the URL to the Websocket for the PG Proxy (all new connections will use this URL)
* `{\"sessionId\": \"1f137f5f-43ec-4393-b5e8-bf195015e697\"}` is the JSON string of an object to be merged with all requests

Here, in this example, the JSON string to merge is used by the Proxy Server to authenticate the request. The protocol with the proxy doesn't require this. It's implemenation specific.

[PGProxy](https://github.com/panosoft/elm-pgproxy) delegates authentication to the application allowing for flexible authentication.

N.B. connecting to the Database should NOT be done until the `Configured` message has been received. That's because the trasport between the client and the proxy is Websockets.

> Turn on debugging

This will print out debugging information during operations. This should only be used in Development or Test. If this Effects Manager is used on the client-side, then
internal marshalling is printed out, i.e. Sends and Receives.

```elm
debug : Bool -> Cmd msg
debug debug
```

__Usage__

```elm
Postgres.debug True
```

> Dump internal state

This is for debugging purposes to help make sure database connections are leaking.

```elm
dumpState : Cmd msg
dumpState
```

__Usage__

```elm
Postgres.dumpState
```


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
Postgres.listen ErrorListenUnlisten SuccessListenUnlisten ListenEvent 123 "myChannel"
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
