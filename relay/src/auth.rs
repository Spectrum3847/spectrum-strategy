use crate::config::write_private;
use crate::firebase_config::DATA_API_KEY;
use crate::timeutil::now_ms;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::Path;
use std::time::Duration;

pub const SECURE_TOKEN: &str = "https://securetoken.googleapis.com";

const REFRESH_MARGIN_MS: i64 = 5 * 60_000;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StoredToken {
    pub refresh_token: String,
    pub uid: String,
    pub email: String,
}

pub fn load_token(path: &Path) -> Option<StoredToken> {
    let text = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&text).ok()
}

pub fn save_token(path: &Path, token: &StoredToken) -> Result<(), String> {
    write_private(
        path,
        &serde_json::to_vec_pretty(token).map_err(|e| e.to_string())?,
    )
}

pub fn clear_token(path: &Path) {
    let _ = std::fs::remove_file(path);
}

#[derive(Debug)]
pub enum AuthError {

    Refused(String),

    Transient(String),
}

impl std::fmt::Display for AuthError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Refused(m) | Self::Transient(m) => f.write_str(m),
        }
    }
}

pub struct Refreshed {
    pub id_token: String,
    pub refresh_token: String,
    pub uid: String,
    pub expires_at_ms: i64,
}

pub fn refresh(endpoint: &str, refresh_token: &str) -> Result<Refreshed, AuthError> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .http_status_as_error(false)
        .timeout_global(Some(Duration::from_secs(30)))
        .build()
        .into();
    let url = format!(
        "{}/v1/token?key={DATA_API_KEY}",
        endpoint.trim_end_matches('/')
    );
    let mut response = agent
        .post(&url)
        .send_form([
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh_token),
        ])
        .map_err(|e| AuthError::Transient(format!("network: {e}")))?;
    let status = response.status().as_u16();
    let body: Value = response.body_mut().read_json().unwrap_or(Value::Null);
    if status == 400 {
        let reason = body
            .pointer("/error/message")
            .and_then(Value::as_str)
            .unwrap_or("rejected");
        return Err(AuthError::Refused(format!(
            "Sign-in no longer valid ({reason})"
        )));
    }
    if status != 200 {
        return Err(AuthError::Transient(format!("token service HTTP {status}")));
    }
    let field = |key: &str| body.get(key).and_then(Value::as_str).map(str::to_owned);
    let expires_in: i64 = field("expires_in")
        .and_then(|s| s.parse().ok())
        .unwrap_or(3600);
    match (field("id_token"), field("refresh_token"), field("user_id")) {
        (Some(id_token), Some(refresh_token), Some(uid)) => Ok(Refreshed {
            id_token,
            refresh_token,
            uid,
            expires_at_ms: now_ms() + expires_in * 1000,
        }),
        _ => Err(AuthError::Transient(
            "token service sent an incomplete reply".into(),
        )),
    }
}

pub struct Session {
    endpoint: String,
    cached: Option<(String, String, i64)>,
}

impl Session {
    pub fn new(endpoint: &str) -> Self {
        Self {
            endpoint: endpoint.into(),
            cached: None,
        }
    }

    pub fn id_token(
        &mut self,
        stored: &StoredToken,
        token_path: &Path,
    ) -> Result<String, AuthError> {
        if let Some((refresh, id, expiry)) = &self.cached
            && *refresh == stored.refresh_token
            && *expiry - now_ms() > REFRESH_MARGIN_MS
        {
            return Ok(id.clone());
        }
        let fresh = refresh(&self.endpoint, &stored.refresh_token)?;
        if fresh.refresh_token != stored.refresh_token {
            let rotated = StoredToken {
                refresh_token: fresh.refresh_token.clone(),
                ..stored.clone()
            };
            if let Err(e) = save_token(token_path, &rotated) {
                eprintln!("could not save the rotated token: {e}");
            }
        }
        self.cached = Some((
            fresh.refresh_token,
            fresh.id_token.clone(),
            fresh.expires_at_ms,
        ));
        Ok(fresh.id_token)
    }
}
