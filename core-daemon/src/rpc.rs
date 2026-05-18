use tokio::net::UnixStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use serde::{Deserialize, Serialize};
use crate::policy::PolicyEngine;

#[derive(Deserialize, Serialize)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    pub method: String,
    pub params: serde_json::Value,
    pub id: serde_json::Value,
}

#[derive(Serialize)]
pub struct JsonRpcResponse {
    pub jsonrpc: String,
    pub result: Option<serde_json::Value>,
    pub error: Option<serde_json::Value>,
    pub id: serde_json::Value,
}

pub async fn handle_connection(mut stream: UnixStream) -> Result<(), Box<dyn std::error::Error>> {
    let mut buffer = [0; 4096];
    let policy_engine = PolicyEngine::new();

    loop {
        let bytes_read = match stream.read(&mut buffer).await {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) => return Err(Box::new(e)),
        };

        let req_data = &buffer[..bytes_read];
        let response = match serde_json::from_slice::<JsonRpcRequest>(req_data) {
            Ok(req) => {
                if req.jsonrpc != "2.0" {
                    make_error_response(req.id, -32600, "Invalid JSON-RPC 2.0 Request Frame Specifier")
                } else {
                    match policy_engine.validate_and_execute(&req.method, &req.params) {
                        Ok(res) => JsonRpcResponse {
                            jsonrpc: "2.0".to_string(),
                            result: Some(res),
                            error: None,
                            id: req.id,
                        },
                        Err(e) => make_error_response(req.id, -32000, &e.to_string()),
                    }
                }
            }
            Err(_) => make_error_response(serde_json::Value::Null, -32700, "Parse Error: Broken Payload Fragment"),
        };

        let resp_bytes = match serde_json::to_vec(&response) {
            Ok(b) => b,
            Err(e) => return Err(Box::new(e)),
        };

        match stream.write_all(&resp_bytes).await {
            Ok(_) => {}
            Err(e) => return Err(Box::new(e)),
        }
    }
    Ok(())
}

fn make_error_response(id: serde_json::Value, code: i32, message: &str) -> JsonRpcResponse {
    JsonRpcResponse {
        jsonrpc: "2.0".to_string(),
        result: None,
        error: Some(serde_json::json!({ "code": code, "message": message })),
        id,
    }
}