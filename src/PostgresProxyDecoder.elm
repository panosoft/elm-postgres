module PostgresProxyDecoder
    exposing
        ( decodeRequest
        , ProxyRequest(..)
        )

{-| Postgres Proxy Decoder

This is for decoding the proxy messages between client and server

@docs decodeRequest, ProxyRequest

-}

import Json.Decode as JD exposing (..)


type alias RequestType =
    String


type alias ConnectRequest =
    { host : String
    , port_ : Int
    , database : String
    , user : String
    , password : String
    }


type alias DisconnectRequest =
    { discardConnection : Bool
    }


type alias QueryRequest =
    { sql : String
    , recordCount : Int
    }


type alias MoreQueryResultsRequest =
    {}


type alias ExecuteSqlRequest =
    { sql : String
    }


type alias ListenRequest =
    { channel : String
    }


type alias UnlistenRequest =
    { channel : String
    }


{-| Proxy requests
-}
type ProxyRequest
    = Connect ConnectRequest
    | Disconnect DisconnectRequest
    | Query QueryRequest
    | MoreQueryResults MoreQueryResultsRequest
    | ExecuteSql ExecuteSqlRequest
    | Listen ListenRequest
    | Unlisten UnlistenRequest
    | Unknown String


(///) : Result err value -> (err -> value) -> value
(///) result f =
    case result of
        Ok value ->
            value

        Err err ->
            f err


(<||) : JD.Decoder (a -> b) -> JD.Decoder a -> JD.Decoder b
(<||) =
    JD.object2 (<|)


requestTypeDecoder : JD.Decoder RequestType
requestTypeDecoder =
    "func" := string


connectDecoder : JD.Decoder ProxyRequest
connectDecoder =
    JD.succeed Connect
        <|| (JD.succeed ConnectRequest
                <|| ("host" := string)
                <|| ("port" := int)
                <|| ("database" := string)
                <|| ("user" := string)
                <|| ("password" := string)
            )


disconnectDecoder : JD.Decoder ProxyRequest
disconnectDecoder =
    JD.succeed Disconnect
        <|| (JD.succeed DisconnectRequest
                <|| ("discardConnection" := bool)
            )


queryDecoder : JD.Decoder ProxyRequest
queryDecoder =
    JD.succeed Query
        <|| (JD.succeed QueryRequest
                <|| ("sql" := string)
                <|| ("recordCount" := int)
            )


moreQueryResultsDecoder : JD.Decoder ProxyRequest
moreQueryResultsDecoder =
    JD.succeed MoreQueryResults
        <|| JD.succeed MoreQueryResultsRequest


executeSqlDecoder : JD.Decoder ProxyRequest
executeSqlDecoder =
    JD.succeed ExecuteSql
        <|| (JD.succeed ExecuteSqlRequest
                <|| ("sql" := string)
            )


listenDecoder : JD.Decoder ProxyRequest
listenDecoder =
    JD.succeed Listen
        <|| (JD.succeed ListenRequest
                <|| ("channel" := string)
            )


unlistenDecoder : JD.Decoder ProxyRequest
unlistenDecoder =
    JD.succeed Unlisten
        <|| (JD.succeed UnlistenRequest
                <|| ("channel" := string)
            )


{-| Decode JSON Postgres Proxy Request
-}
decodeRequest : String -> Result String ProxyRequest
decodeRequest json =
    let
        func =
            JD.decodeString requestTypeDecoder json /// (\_ -> "MISSING_FUNC_KEY")

        decoder =
            case func of
                "connect" ->
                    connectDecoder

                "disconnect" ->
                    disconnectDecoder

                "query" ->
                    queryDecoder

                "moreQueryResults" ->
                    moreQueryResultsDecoder

                "executeSql" ->
                    executeSqlDecoder

                "listen" ->
                    listenDecoder

                "unlisten" ->
                    unlistenDecoder

                _ ->
                    JD.succeed <| Unknown ("Unknown request:" ++ func ++ " in: " ++ json)
    in
        JD.decodeString decoder json
