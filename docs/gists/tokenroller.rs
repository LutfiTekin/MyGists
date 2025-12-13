use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use rand::{thread_rng, Rng};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::PathBuf,
    process::Command,
    sync::Arc,
};
use tokio::task;

use crate::config::AppConfig;

#[derive(Clone)]
pub struct TokenState {
    backend_dir: Arc<PathBuf>,
    token_file: Arc<PathBuf>,
    port_file: Arc<PathBuf>,
}

#[derive(Serialize)]
struct RollResponse {
    token: String,
    port: u16,
    r#async: bool,
}

#[derive(Serialize)]
struct CurrentResponse {
    token: String,
    port: u16,
}

#[derive(Deserialize)]
struct CheckQuery {
    token: String,
}

pub fn router() -> Router {
    // Load unified config once, using binary-relative app_config.json
    let cfg = AppConfig::load_from_default()
        .expect("Failed to load app_config.json via AppConfig");

    let state = TokenState {
        backend_dir: Arc::new(cfg.backend_dir.clone()),
        token_file: Arc::new(cfg.token_file.clone()),
        port_file: Arc::new(cfg.port_file.clone()),
    };

    Router::new()
        .route("/roll", get(roll))
        .route("/current", get(current))
        .route("/check", get(check))
        .with_state(state)
}

async fn roll(
    Query(params): Query<std::collections::HashMap<String, String>>,
    State(state): State<TokenState>,
) -> Json<RollResponse> {
    let async_flag = params
        .get("async")
        .map(|v| matches!(v.as_str(), "1" | "true" | "yes"))
        .unwrap_or(true);

    let (token, port) = roll_token_and_port(&state).await;

    if async_flag {
        let port_copy = port;
        task::spawn(async move {
            restart_vidapi(port_copy);
        });
    } else {
        restart_vidapi(port);
    }

    Json(RollResponse {
        token,
        port,
        r#async: async_flag,
    })
}

async fn current(State(state): State<TokenState>) -> axum::response::Result<Json<CurrentResponse>> {
    let token = fs::read_to_string(&*state.token_file)
        .unwrap_or_default()
        .trim()
        .to_string();

    let port_str = fs::read_to_string(&*state.port_file)
        .unwrap_or_default()
        .trim()
        .to_string();

    if token.is_empty() || port_str.is_empty() {
        return Err(axum::http::StatusCode::NOT_FOUND.into());
    }

    let port = port_str.parse::<u16>().unwrap_or(0);

    Ok(Json(CurrentResponse { token, port }))
}

async fn check(
    Query(q): Query<CheckQuery>,
    State(state): State<TokenState>,
) -> Json<bool> {
    let stored = fs::read_to_string(&*state.token_file)
        .unwrap_or_default()
        .trim()
        .to_string();

    Json(constant_time_eq(&stored, &q.token))
}

// -----------------------------------------------------------
// Core logic
// -----------------------------------------------------------

async fn roll_token_and_port(state: &TokenState) -> (String, u16) {
    let mut rng = thread_rng();
    let token = hex::encode((0..32).map(|_| rng.gen::<u8>()).collect::<Vec<u8>>());
    let port: u16 = rng.gen_range(30000..50000);

    let _ = fs::create_dir_all(&*state.backend_dir);
    let _ = fs::write(&*state.token_file, &token);
    let _ = fs::write(&*state.port_file, port.to_string());

    (token, port)
}

fn restart_vidapi(_port: u16) {
    // Same behavior as Python: just restart vidapi, it reads port.txt itself
    let _ = Command::new("sudo")
        .arg("systemctl")
        .arg("restart")
        .arg("vidapi")
        .output();
}

// -----------------------------------------------------------
// Constant time compare
// -----------------------------------------------------------

fn constant_time_eq(a: &str, b: &str) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut res = 0u8;
    for (x, y) in a.bytes().zip(b.bytes()) {
        res |= x ^ y;
    }
    res == 0
}
