// Elm globals (some for elm-native-helpers and some for us and some for the future)
const E = {
	A2: A2,
	A3: A3,
	A4: A4,
	sendToApp: _elm_lang$core$Native_Platform.sendToApp,
	Scheduler: {
		nativeBinding: _elm_lang$core$Native_Scheduler.nativeBinding,
		succeed:  _elm_lang$core$Native_Scheduler.succeed,
		fail: _elm_lang$core$Native_Scheduler.fail,
		rawSpawn: _elm_lang$core$Native_Scheduler.rawSpawn
	},
	List: {
		fromArray: _elm_lang$core$Native_List.fromArray
	},
	Maybe: {
		Nothing: _elm_lang$core$Maybe$Nothing,
		Just: _elm_lang$core$Maybe$Just
	},
	Result: {
		Err: _elm_lang$core$Result$Err,
		Ok: _elm_lang$core$Result$Ok
	},
	Tuple: {
		tuple2: _elm_lang$core$Native_Utils.Tuple2
	}
};
// This module is in the same scope as Elm but all modules that are required are NOT
// So we must pass elm globals to it (see https://github.com/panosoft/elm-native-helpers for the minimum of E)
const helper = require('@panosoft/elm-native-helpers/helper')(E);
var native;
//////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////
// NODE
//////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////
if (!process.env.BROWSER) {
	const read = require('stream-read');
	const pg = require('pg');
	const QueryStream = require('pg-query-stream');

	// HACK to keep pool from throwing uncatchable exeception on connection errors
	// god I hate the pg library
	pg.on('error', err => err);

	const createConnectionUrl = (host, port, database, user, password) => `postgres://${user}:${password}@${host}:${port}/${database}`;
	native = _ => {
		//////////////////////////////////////////////////////////////////////////////////////////////////////////
		// Cmds
		const _disconnectInternal = (dbClient, discardConnection, nativeListener) => {
			if (nativeListener)
				dbClient.client.removeListener('error', nativeListener);
			// pooled client
			// passing truthy err will destroy client rather than returning client to pool.
			if (dbClient.releaseClient)
				dbClient.releaseClient(discardConnection);
			// non-pooled client
			else
				dbClient.client.end();
		};
		const _disconnect = (dbClient, discardConnection, nativeListener, cb) => {
			try {
				_disconnectInternal(dbClient, discardConnection, nativeListener);
				cb();
			}
			catch (err) {
				cb(err.message);
			}
		};
		const _connect = (timeout, host, port, database, user, password, connectionLostCb, cb) => {
			var expired = false;
			const timer = setTimeout(_ => {
				expired = true;
				cb(`Connection timeout after ${timeout/1000} seconds to ${host}:${port}/${database}`);
			}, timeout);
			pg.connect(createConnectionUrl(host, port, database, user, password), (err, client, done) => {
				try {
					clearTimeout(timer);
					if (expired)
						_disconnectInternal(dbClient, false);
					else {
						if (err)
							cb(`Attempt to retrieve pooled connection for ${host}:${port}/${database}.  Failed with: ${err.message}`);
						else {
							const dbClient = {client: client, releaseClient: done};
							const nativeListener = err => {
								try {
									_disconnectInternal(dbClient, true, nativeListener);
									E.Scheduler.rawSpawn(connectionLostCb(err.message));
								}
								catch (err) {
									// eat this error since we have a bad connection anyway
									console.error("SHOULD NEVER GET HERE");
								}
							};
							dbClient.client.on('error', nativeListener);
							cb(null, dbClient, nativeListener);
						}
					}
				}
				catch(err) {
					cb(err);
				}
			});
		};
		const _query = (dbClient, sql, recordCount, nativeListener, cb) => {
			const options = {
				highWaterMark: 16 * 1024, // total number of rows buffered per DB access (used by readable-stream)
				batchSize: 1024 // number of rows read from underlying stream at a time (used by pg)
			};
			const stream = dbClient.client.query(new QueryStream(sql, null, options));
			stream.on('error', errMsg => {
				nativeListener('Stream error: ' + errMsg);
			});
			return _moreQueryResults(dbClient, stream, recordCount, cb);
		};
		const _moreQueryResults = (dbClient, stream, recordCount, cb) => {
			var records = [];
			var count = 0;
			const processData = (err, data) => {
				if (err)
					cb(err.message);
				else {
					try {
						if (data)
							records[records.length] = JSON.stringify(data);
						if (!data || ++count >= recordCount) {
							cb(null, stream, E.List.fromArray(records));
							return;
						}
						read(stream, processData);
					}
					catch (err) {
						cb(err.message);
					}
				}
			};
			read(stream, processData);
		};
		const _executeSql = (dbClient, sql, cb) => {
			try {
				dbClient.client.query(sql, (err, result) => {
					if (err)
						cb(err.message);
					else
						cb(null, result.rowCount || 0);
				});
			}
			catch(err) {
				cb(err.message);
			}
		};
		//////////////////////////////////////////////////////////////////////////////////////////////////////////
		// Subs
		const _listen = (dbClient, sql, routeCb, cb) => {
			_executeSql(dbClient, sql, (err, _) => {
				const nativeListener = message => {
					E.Scheduler.rawSpawn(routeCb(message.payload));
				};
				dbClient.client.on('notification', nativeListener);
				cb(null, nativeListener);
			});
		};
		const _unlisten = (dbClient, sql, nativeListener, cb) => {
			_executeSql(dbClient, sql, (err, _) => {
				dbClient.client.removeListener('notification', nativeListener);
				cb();
			});
		};
		//////////////////////////////////////////////////////////////////////////////////////////////////////////
		// Cmds
		const connect = helper.call7_2(_connect);
		const disconnect = helper.call3_0(_disconnect, helper.unwrap({1:'_0', 3:'_0'}));
		const query = helper.call4_2(_query, helper.unwrap({1:'_0', 4:'_0'}));
		const moreQueryResults = helper.call3_2(_moreQueryResults, helper.unwrap({1:'_0'}));
		const executeSql = helper.call2_1(_executeSql, helper.unwrap({1:'_0'}));
		//////////////////////////////////////////////////////////////////////////////////////////////////////////
		// Subs
		const listen = helper.call3_1(_listen, helper.unwrap({1:'_0'}));
		const unlisten = helper.call3_0(_unlisten, helper.unwrap({1:'_0'}));

		return {
			///////////////////////////////////////////
			// Cmds
			connect: F8(connect),
			disconnect: F4(disconnect),
			query: F5(query),
			moreQueryResults: F4(moreQueryResults),
			executeSql: F3(executeSql),
			///////////////////////////////////////////
			// Subs
			listen: F4(listen),
			unlisten: F4(unlisten)
		};
	};
}
//////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////
// BROWSER
//////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////
else {
	const merge = (o1, o2) => {
		const newObj = {};
		const add = (dest, src) => Object.keys(src).forEach(key => dest[key] = src[key]);
		add(newObj, o1);
		add(newObj, o2);
		return newObj;
	};
	native = _ => {
		var _router;
		var _badResponseMsg;
		var _wsUrl;
		var _additionalSendData;
		const _send = (ws, handler, message) => {
			// set message handler
			ws.__messageHandler__ = handler;
			// add addtional keys
			message = merge(message, _additionalSendData);
			ws.send(JSON.stringify(message));
		};
		const idleMessageHandler = ws => event => handleResponse(ws, event.data, _ => _);
		const handleResponse = (ws, event, errorCb, successCb) => {
			// reset message handler
			ws.__messageHandler__ = idleMessageHandler(ws);
			// check for proxy losing connection to DB
			try {
				const response = JSON.parse(event.data);
				if (!response.success && response.connectionLostError) {
					ws.__connectionLostCb__(response.connectionLostError);
					ws.__connectionLostAlreadySent__ = true;
					ws.close();
				}
				else if (response.error)
					errorCb(response.error);
				// do SUCCESS handling
				else
					successCb(response);
			}
			catch (err) {
				// send bad response message to app
				E.Scheduler.rawSpawn(A2(E.sendToApp, _router, _badResponseMsg(E.Tuple.tuple2(event.data, err.message))));
			}
		};
		const wsCloseReason = event => {
			// See http://tools.ietf.org/html/rfc6455#section-7.4.1
	        if (event.code == 1000)
	            return "Normal closure, meaning that the purpose for which the connection was established has been fulfilled.";
	        else if(event.code == 1001)
	            return "An endpoint is \"going away\", such as a server going down or a browser having navigated away from a page.";
	        else if(event.code == 1002)
	            return "An endpoint is terminating the connection due to a protocol error";
	        else if(event.code == 1003)
	            return "An endpoint is terminating the connection because it has received a type of data it cannot accept (e.g., an endpoint that understands only text data MAY send this if it receives a binary message).";
	        else if(event.code == 1004)
	            return "Reserved. The specific meaning might be defined in the future.";
	        else if(event.code == 1005)
	            return "No status code was actually present.";
	        else if(event.code == 1006)
	           return "The connection was closed abnormally, e.g., without sending or receiving a Close control frame";
	        else if(event.code == 1007)
	            return "An endpoint is terminating the connection because it has received data within a message that was not consistent with the type of the message (e.g., non-UTF-8 [http://tools.ietf.org/html/rfc3629] data within a text message).";
	        else if(event.code == 1008)
	            return "An endpoint is terminating the connection because it has received a message that \"violates its policy\". This reason is given either if there is no other sutible reason, or if there is a need to hide specific details about the policy.";
	        else if(event.code == 1009)
	           return "An endpoint is terminating the connection because it has received a message that is too big for it to process.";
	        else if(event.code == 1010) // Note that this status code is not used by the server, because it can fail the WebSocket handshake instead.
	            return "An endpoint (client) is terminating the connection because it has expected the server to negotiate one or more extension, but the server didn't return them in the response message of the WebSocket handshake. <br /> Specifically, the extensions that are needed are: " + event.reason;
	        else if(event.code == 1011)
	            return "A server is terminating the connection because it encountered an unexpected condition that prevented it from fulfilling the request.";
	        else if(event.code == 1015)
	            return "The connection was closed due to a failure to perform a TLS handshake (e.g., the server certificate can't be verified).";
	        else
	            return "Unknown reason";
		};
		//////////////////////////////////////////////////////////////////////////////////////////////////////////
		// Cmds
		const _connect = (timeout, host, port, database, user, password, connectionLostCb, cb) => {
			try {
				// make sure client configuration has been done before sending anything
				if (!_wsUrl)
					throw Error('Postgres Effects Manager cannot be used on the front-end without first calling "clientSideConfig"');
				const ws = new WebSocket(_wsUrl);
				ws.__open__ = false;
				ws.__connectionLostCb__ = connectionLostCb;
	            ws.addEventListener('open', _ => {
					ws.__open__ = true;
					// send to proxy
					_send(ws, event => handleResponse(ws, event, cb, response => cb(null, ws, null)), {
						func: 'connect',
						host, port, database, user, password
					});
				});
	            ws.addEventListener('message', event => ws.__messageHandler__(event));
				ws.__closeHandler__ = event => {
					if (ws.__open__) {
						if (!ws.__connectionLostAlreadySent__)
							E.Scheduler.rawSpawn(connectionLostCb('Websocket to proxy prematurely closed'));
						ws.__connectionLostAlreadySent__ = false;
						ws.__open__ = false;
					}
					else
						cb(wsCloseReason(event));
				};
	            ws.addEventListener('close', ws.__closeHandler__);
			}
	        catch (err) {
	            cb(err.message)
	        }
		};
		const _disconnect = (dbClient, discardConnection, nativeListener, cb) => {
			try {
				const ws = dbClient;
				// send to proxy
				_send(ws, event => handleResponse(ws, event, cb, response => {
					ws.removeEventListener('close', ws.__closeHandler__);
					ws.close();
					cb();
				}), {
					func: 'disconnect',
					discardConnection
				});
			}
			catch (err) {
	            cb(err.message)
	        }
		};
		const _query = (dbClient, sql, recordCount, nativeListener, cb) => {
			try {
				const ws = dbClient;
				// send to proxy
				_send(ws, event => handleResponse(ws, event, cb, response => {
					cb(null, null, E.List.fromArray(response.records));
				}), {
					func: 'query',
					sql, recordCount
				});
			}
			catch (err) {
	            cb(err.message)
	        }
		};
		const _moreQueryResults = (dbClient, stream, recordCount, cb) => {
			try {
				const ws = dbClient;
				// send to proxy
				_send(ws, event => handleResponse(ws, event, cb, response => {
					cb(null, null, E.List.fromArray(response.records));
				}), {
					func: 'moreQueryResults'
				});
			}
			catch (err) {
	            cb(err.message)
	        }
		};
		const _executeSql = (dbClient, sql, cb) => {
			try {
				const ws = dbClient;
				// send to proxy
				_send(ws, event => handleResponse(ws, event, cb, response => {
					cb(null, response.count);
				}), {
					func: 'executeSql',
					sql
				});
			}
			catch (err) {
	            cb(err.message)
	        }
		};
		const _clientSideConfig = (router, badResponseMsg, wsUrl, additionalSendDataStr, cb) => {
			try {
				_router = router;
				_badResponseMsg = badResponseMsg;
				_wsUrl = wsUrl || _wsUrl;
				_additionalSendData = additionalSendDataStr ? JSON.parse(additionalSendDataStr) : {};
				cb();
			}
			catch (err) {
				cb(err.message);
			}
		};
		//////////////////////////////////////////////////////////////////////////////////////////////////////////
		// Subs
		const _listen = (dbClient, sql, routeCb, cb) => {
		};
		const _unlisten = (dbClient, sql, nativeListener, cb) => {
		};
		//////////////////////////////////////////////////////////////////////////////////////////////////////////
		// Cmds
		const connect = helper.call7_2(_connect);
		const disconnect = helper.call3_0(_disconnect, helper.unwrap({1:'_0', 3:'_0'}));
		const query = helper.call4_2(_query, helper.unwrap({1:'_0', 4:'_0'}));
		const moreQueryResults = helper.call3_2(_moreQueryResults, helper.unwrap({1:'_0'}));
		const executeSql = helper.call2_1(_executeSql, helper.unwrap({1:'_0'}));
		const clientSideConfig = helper.call4_0(_clientSideConfig, helper.unwrap({3:'_0', 4: '_0'}));
		//////////////////////////////////////////////////////////////////////////////////////////////////////////
		// Subs
		const listen = helper.call3_1(_listen, helper.unwrap({1:'_0'}));
		const unlisten = helper.call3_0(_unlisten, helper.unwrap({1:'_0'}));

		return {
			///////////////////////////////////////////
			// Cmds
			connect: F8(connect),
			disconnect: F4(disconnect),
			query: F5(query),
			moreQueryResults: F4(moreQueryResults),
			executeSql: F3(executeSql),
			clientSideConfig: F5(clientSideConfig),
			///////////////////////////////////////////
			// Subs
			listen: F4(listen),
			unlisten: F4(unlisten)
		};
	};

}
const _panosoft$elm_postgres$Native_Postgres = native();
// for local testing
const _user$project$Native_Postgres = _panosoft$elm_postgres$Native_Postgres;
