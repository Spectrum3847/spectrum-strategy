use crate::auth::{self, SECURE_TOKEN, StoredToken};
use crate::autostart;
use crate::config::ModelSpec;
use crate::firebase_config as fb;
use crate::service::Shared;
use crate::update;
use serde_json::{Value, json};
use std::io::Read;
use std::sync::Arc;
use tiny_http::{Header, Method, Request, Response, Server};

const PAGE: &str = include_str!("gui.html");
const MAX_BODY: u64 = 64 * 1024;

pub fn bind(port: u16) -> Result<Server, String> {
    Server::http(("127.0.0.1", port)).map_err(|e| e.to_string())
}

pub fn url(port: u16) -> String {
    format!("http://localhost:{port}/")
}

pub fn request_allowed(host: Option<&str>, origin: Option<&str>, port: u16) -> bool {
    let hosts = [format!("localhost:{port}"), format!("127.0.0.1:{port}")];
    if !host.is_some_and(|h| hosts.iter().any(|ok| ok == h)) {
        return false;
    }
    origin.is_none_or(|o| hosts.iter().any(|ok| *o == format!("http://{ok}")))
}

fn header(request: &Request, name: &str) -> Option<String> {
    request
        .headers()
        .iter()
        .find(|h| h.field.as_str().as_str().eq_ignore_ascii_case(name))
        .map(|h| h.value.to_string())
}

fn page(port: u16) -> String {
    let config = json!({
        "central": {
            "apiKey": fb::CENTRAL_API_KEY,
            "projectId": fb::CENTRAL_PROJECT_ID,
            "authDomain": fb::CENTRAL_AUTH_DOMAIN,
        },
        "data": {
            "apiKey": fb::DATA_API_KEY,
            "projectId": fb::DATA_PROJECT_ID,
            "authDomain": fb::DATA_AUTH_DOMAIN,
        },
        "appKey": fb::APP_KEY,
        "callable": fb::CUSTOM_TOKEN_CALLABLE,
        "port": port,
    });
    PAGE.replace(
        "__RELAY_CONFIG__",
        &config.to_string().replace("</", "<\\/"),
    )
}

fn status(shared: &Shared) -> Value {
    let state = shared.state();
    let config = shared.config();
    json!({
        "enabled": config.enabled,
        "autostart": autostart::is_installed(),
        "signedInAs": state.signed_in_as,
        "signedInUid": state.signed_in_uid,
        "phase": state.phase,
        "llamaRunning": state.llama_running,
        "model": config.model,
        "defaultModel": ModelSpec::default(),
        "lastAnswer": state.last_answer,
        "lastError": state.last_error,
        "build": update::BUILD,
        "autoUpdate": config.auto_update,
        "update": state.update,
        "chat": {
            "online": state.chat_online,
            "peers": state.chat_peers,
            "lastError": state.chat_error,
        },
    })
}

fn body_json(request: &mut Request) -> Result<Value, String> {
    let mut text = String::new();
    request
        .as_reader()
        .take(MAX_BODY)
        .read_to_string(&mut text)
        .map_err(|e| e.to_string())?;
    serde_json::from_str(&text).map_err(|e| format!("bad request: {e}"))
}

fn link(shared: &Shared, body: &Value) -> Result<Value, String> {
    let refresh_token = body["refreshToken"].as_str().filter(|t| !t.is_empty());
    let refresh_token = refresh_token.ok_or("no refresh token")?;
    let email = body["email"].as_str().unwrap_or_default();
    let fresh = auth::refresh(SECURE_TOKEN, refresh_token).map_err(|e| e.to_string())?;
    let stored = StoredToken {
        refresh_token: fresh.refresh_token,
        uid: fresh.uid,
        email: if email.is_empty() {
            "a team member".into()
        } else {
            email.into()
        },
    };
    auth::save_token(&shared.dirs.token_file(), &stored)?;
    shared.update_state(|s| {
        s.signed_in_as = Some(stored.email.clone());
        s.signed_in_uid = Some(stored.uid.clone());
    });
    shared.nudge();
    Ok(json!({ "ok": true }))
}

fn model(shared: &Shared, body: &Value) -> Result<Value, String> {
    let field = |key: &str| body[key].as_str().unwrap_or_default().trim().to_string();
    let mut spec = ModelSpec {
        name: field("name"),
        url: field("url"),
        sha256: field("sha256").to_lowercase(),
    };
    if !spec.url.starts_with("https://") {
        return Err("The URL must start with https://".into());
    }
    if !spec.sha256.is_empty()
        && (spec.sha256.len() != 64 || !spec.sha256.bytes().all(|b| b.is_ascii_hexdigit()))
    {
        return Err("The SHA-256 must be 64 hex characters, or empty".into());
    }
    if spec.name.is_empty() {
        spec.name = spec.file_name().trim_end_matches(".gguf").to_string();
    }
    shared.update_config(|c| c.model = spec)?;
    Ok(json!({ "ok": true }))
}

fn enabled(shared: &Shared, body: &Value) -> Result<Value, String> {
    let on = body["enabled"]
        .as_bool()
        .ok_or("enabled must be true or false")?;
    shared.update_config(|c| c.enabled = on)?;
    let result = if on {
        std::env::current_exe()
            .map_err(|e| e.to_string())
            .and_then(|exe| autostart::install(&exe, false, &shared.dirs.relay_log()))
    } else {
        autostart::uninstall(false)
    };
    let message = result.unwrap_or_else(|e| format!("Auto start was not changed: {e}"));
    Ok(json!({ "ok": true, "message": message }))
}

fn auto_update(shared: &Shared, body: &Value) -> Result<Value, String> {
    let on = body["enabled"]
        .as_bool()
        .ok_or("enabled must be true or false")?;
    shared.update_config(|c| c.auto_update = on)?;
    Ok(json!({ "ok": true }))
}

fn route(shared: &Shared, request: &mut Request) -> Result<Value, (u16, String)> {
    let path = request.url().split('?').next().unwrap_or("").to_string();
    let post = *request.method() == Method::Post;
    let bad = |e: String| (400, e);
    match (post, path.as_str()) {
        (false, "/api/status") => Ok(status(shared)),
        (true, "/api/link") => link(shared, &body_json(request).map_err(bad)?).map_err(bad),
        (true, "/api/model") => model(shared, &body_json(request).map_err(bad)?).map_err(bad),
        (true, "/api/enabled") => enabled(shared, &body_json(request).map_err(bad)?).map_err(bad),
        (true, "/api/autoupdate") => {
            auto_update(shared, &body_json(request).map_err(bad)?).map_err(bad)
        }
        (true, "/api/updatenow") => {
            shared.request_update_check();
            Ok(json!({ "ok": true }))
        }
        (true, "/api/signout") => {
            auth::clear_token(&shared.dirs.token_file());
            shared.update_state(|s| {
                s.signed_in_as = None;
                s.signed_in_uid = None;
            });
            shared.nudge();
            Ok(json!({ "ok": true }))
        }
        _ => Err((404, "not found".into())),
    }
}

fn content_type(value: &str) -> Header {
    Header::from_bytes("Content-Type", value).unwrap()
}

fn handle(shared: &Shared, mut request: Request, port: u16) {
    let allowed = request_allowed(
        header(&request, "Host").as_deref(),
        header(&request, "Origin").as_deref(),
        port,
    );
    let (status, body, kind) = if !allowed {
        (403, "forbidden".to_string(), "text/plain")
    } else if *request.method() == Method::Get && request.url().split('?').next() == Some("/") {
        (200, page(port), "text/html; charset=utf-8")
    } else {
        match route(shared, &mut request) {
            Ok(value) => (200, value.to_string(), "application/json"),
            Err((code, error)) => (
                code,
                json!({ "error": error }).to_string(),
                "application/json",
            ),
        }
    };
    let response = Response::from_string(body)
        .with_status_code(status)
        .with_header(content_type(kind))
        .with_header(Header::from_bytes("Cache-Control", "no-store").unwrap());
    let _ = request.respond(response);
}

pub fn serve(server: Server, shared: Arc<Shared>, port: u16) {
    for request in server.incoming_requests() {
        handle(&shared, request, port);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{DEFAULT_MODEL_NAME, DEFAULT_MODEL_SHA256, DEFAULT_MODEL_URL};

    #[test]
    fn accepts_local_hosts_only() {
        assert!(request_allowed(Some("localhost:47821"), None, 47821));
        assert!(request_allowed(Some("127.0.0.1:47821"), None, 47821));
        assert!(!request_allowed(Some("evil.test:47821"), None, 47821));
        assert!(!request_allowed(Some("localhost:1"), None, 47821));
        assert!(!request_allowed(None, None, 47821));
    }

    #[test]
    fn rejects_a_foreign_origin() {
        let host = Some("localhost:47821");
        assert!(request_allowed(host, Some("http://localhost:47821"), 47821));
        assert!(!request_allowed(host, Some("https://evil.test"), 47821));
        assert!(!request_allowed(host, Some("http://localhost:9"), 47821));
    }

    #[test]
    fn page_carries_the_sign_in_config() {
        let html = page(47821);
        assert!(!html.contains("__RELAY_CONFIG__"));
        assert!(html.contains(fb::CENTRAL_PROJECT_ID));
        assert!(html.contains(fb::APP_KEY));
    }

    #[test]
    fn page_has_no_emoji_or_dash_punctuation() {
        assert!(
            PAGE.chars()
                .all(|c| c != '\u{2014}' && (c as u32) < 0x1F000)
        );
    }

    #[test]
    fn default_model_constants_agree() {
        let spec = ModelSpec::default();
        assert_eq!(spec.name, DEFAULT_MODEL_NAME);
        assert_eq!(spec.url, DEFAULT_MODEL_URL);
        assert_eq!(spec.sha256, DEFAULT_MODEL_SHA256);
    }
}
