mod rpc;
mod policy;

use tokio::net::UnixListener;
use std::fs;
use std::path::Path;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let socket_path = "/run/aios/core.sock";

    if Path::new(socket_path).exists() {
        match fs::remove_file(socket_path) {
            Ok(_) => {}
            Err(e) => return Err(Box::new(e)),
        }
    }

    if let Some(parent) = Path::new(socket_path).parent() {
        match fs::create_dir_all(parent) {
            Ok(_) => {}
            Err(e) => return Err(Box::new(e)),
        }
    }

    let listener = match UnixListener::bind(socket_path) {
        Ok(l) => l,
        Err(e) => return Err(Box::new(e)),
    };

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                tokio::spawn(async move {
                    match rpc::handle_connection(stream).await {
                        Ok(_) => {}
                        Err(e) => {
                            eprintln!("Execution Error within RPC context channel: {}", e);
                        }
                    }
                });
            }
            Err(e) => {
                eprintln!("Socket Interface Connection Acceptance Exception: {}", e);
            }
        }
    }
}