use std::error::Error;
use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    println!("Starting AiOS Core Daemon Engine...");

    // Socket an die Loopback-Adresse binden
    let address = "127.0.0.1:8080";
    let listener = TcpListener::bind(address).await?;
    println!("AiOS Core Daemon listening on {}", address);

    // Hauptschleife für eingehende Verbindungen
    loop {
        match listener.accept().await {
            Ok((mut stream, addr)) => {
                println!("New connection accepted from: {}", addr);

                // Jede Verbindung in einem eigenen asynchronen Task verarbeiten
                tokio::spawn(async move {
                    let mut buffer = [0; 1024];
                    loop {
                        match stream.read(&mut buffer).await {
                            Ok(0) => {
                                // Verbindung wurde vom Client geschlossen
                                println!("Connection closed by remote peer: {}", addr);
                                break;
                            }
                            Ok(n) => {
                                // Echo-Funktionalität oder Payload-Verarbeitung
                                if let Err(e) = stream.write_all(&buffer[..n]).await {
                                    eprintln!("Failed to write to stream for {}: {}", addr, e);
                                    break;
                                }
                            }
                            Err(e) => {
                                // Hier war der Tippfehler – jetzt korrekt mit eprintln!
                                eprintln!("Failed to read from stream for {}: {}", addr, e);
                                break;
                            }
                        }
                    }
                });
            }
            Err(e) => {
                // Verbindungsfehler werden geloggt, damit der Loop stabil weiterläuft
                eprintln!("Inbound connection failed: {}", e);
            }
        }
    }

    // Dieser Code ist zwar unerrreichbar, aber zwingend notwendig,
    // damit der Rust-Compiler den Rückgabetyp korrekt auflöst.
    #[allow(unreachable_code)]
    Ok(())
}