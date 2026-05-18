use std::process::Command;
use serde_json::Value;

pub struct PolicyEngine;

impl PolicyEngine {
    pub fn new() -> Self {
        PolicyEngine
    }

    pub fn validate_and_execute(&self, method: &str, params: &Value) -> Result<Value, Box<dyn std::error::Error>> {
        match method {
            "compute_inference" => {
                let prompt = match params.get("prompt").and_then(|v| v.as_str()) {
                    Some(p) => p,
                    None => return Err(Box::from("Policy Violation: Missing required prompt payload parameter")),
                };
                self.sandbox_execute(prompt)
            }
            _ => Err(Box::from("Zero-Trust Policy Engine: Action rejected - Unauthorized execution pathway")),
        }
    }

    fn sandbox_execute(&self, prompt: &str) -> Result<Value, Box<dyn std::error::Error>> {
        let output = match Command::new("bwrap")
            .args(&[
                "--ro-bind", "/usr", "/usr",
                "--ro-bind", "/lib", "/lib",
                "--ro-bind", "/lib64", "/lib64",
                "--proc", "/proc",
                "--dev", "/dev",
                "--unshare-all",
                "/usr/bin/echo",
                prompt,
            ])
            .output() {
                Ok(out) => out,
                Err(e) => return Err(Box::new(e)),
            };

        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            Ok(serde_json::json!({ "status": "success", "isolation": "bubblewrap", "payload": stdout }))
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            Err(Box::from(format!("Sandbox Environment Execution Fault: {}", stderr)))
        }
    }
}