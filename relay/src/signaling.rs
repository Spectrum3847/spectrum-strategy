use crate::answer::truncate_utf16;
use serde_json::{Value, json};
use std::time::Duration;

pub const PING: &str = "ping";
pub const PING_EVERY: Duration = Duration::from_secs(30);
pub const TOKEN_EVERY: Duration = Duration::from_secs(45 * 60);

const MAX_ID: usize = 128;
const MAX_NAME: usize = 64;
const MAX_MODEL: usize = 128;
const MAX_BUILD: usize = 32;
const MAX_REJECT: usize = 256;
pub const MAX_SDP: usize = 16384;

const DEFAULT_STUN: [&str; 2] = [
    "stun:stun.cloudflare.com:3478",
    "stun:stun.l.google.com:19302",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IceServer {
    pub urls: Vec<String>,
    pub username: String,
    pub credential: String,
}

pub fn default_ice_servers() -> Vec<IceServer> {
    DEFAULT_STUN
        .iter()
        .map(|url| IceServer {
            urls: vec![(*url).into()],
            username: String::new(),
            credential: String::new(),
        })
        .collect()
}

pub fn hello(relay_id: &str, name: &str, model: &str, build: &str, busy: bool) -> String {
    json!({
        "type": "hello",
        "relayId": truncate_utf16(relay_id, MAX_ID),
        "name": truncate_utf16(name, MAX_NAME),
        "model": truncate_utf16(model, MAX_MODEL),
        "build": truncate_utf16(build, MAX_BUILD),
        "busy": busy,
    })
    .to_string()
}

pub fn busy(busy: bool) -> String {
    json!({ "type": "busy", "busy": busy }).to_string()
}

pub fn token(token: &str) -> String {
    json!({ "type": "token", "token": token }).to_string()
}

pub fn answer(session_id: &str, sdp: &str) -> String {
    json!({ "type": "answer", "sessionId": session_id, "sdp": sdp }).to_string()
}

pub fn reject(session_id: &str, message: &str) -> String {
    let message = truncate_utf16(message, MAX_REJECT);
    let message = if message.is_empty() {
        "the relay could not answer"
    } else {
        &message
    };
    json!({ "type": "reject", "sessionId": session_id, "message": message }).to_string()
}

#[derive(Debug, PartialEq, Eq)]
pub struct Offer {
    pub session_id: String,
    pub sdp: String,

    pub ice_servers: Vec<IceServer>,
}

pub fn parse_offer(text: &str) -> Option<Offer> {
    let value: Value = serde_json::from_str(text).ok()?;
    if value.get("type")?.as_str()? != "offer" {
        return None;
    }
    let text_field = |key: &str| value.get(key)?.as_str().filter(|s| !s.is_empty());
    let sdp = text_field("sdp").filter(|s| s.len() <= MAX_SDP)?;
    Some(Offer {
        session_id: text_field("sessionId")?.into(),
        sdp: sdp.into(),
        ice_servers: usable_ice_servers(value.get("iceServers")),
    })
}

pub fn usable_ice_servers(servers: Option<&Value>) -> Vec<IceServer> {
    let Some(servers) = servers.and_then(Value::as_array) else {
        return Vec::new();
    };
    let text = |server: &Value, key: &str| {
        server
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };
    servers
        .iter()
        .filter_map(|server| {
            let username = text(server, "username");
            let credential = text(server, "credential");
            let listed = match server.get("urls")? {
                Value::String(url) => vec![url.as_str()],
                Value::Array(urls) => urls.iter().filter_map(Value::as_str).collect(),
                _ => return None,
            };
            let has_credentials = !username.is_empty() && !credential.is_empty();
            let urls: Vec<String> = listed
                .into_iter()
                .filter_map(|url| usable_url(url, has_credentials))
                .collect();
            (!urls.is_empty()).then_some(IceServer {
                urls,
                username,
                credential,
            })
        })
        .collect()
}

fn usable_url(url: &str, has_credentials: bool) -> Option<String> {
    let (scheme, rest) = url.split_once(':')?;
    let (address, query) = rest.split_once('?').unwrap_or((rest, ""));
    if address.is_empty() {
        return None;
    }
    match scheme {
        "stun" => Some(format!("stun:{address}")),
        "turn" if has_credentials && matches!(query, "" | "transport=udp") => Some(url.into()),
        _ => None,
    }
}

pub fn computer_name() -> String {
    let from_env = std::env::var("COMPUTERNAME").ok();
    let from_command = || {
        std::process::Command::new("hostname")
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
    };
    from_env
        .or_else(from_command)
        .map(|name| name.trim().to_owned())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| "Spectrum relay".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn offer_message(extra: Value) -> String {
        let mut message = json!({ "type": "offer", "sessionId": "s1", "sdp": "v=0" });
        message
            .as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        message.to_string()
    }

    #[test]
    fn hello_carries_the_hub_fields_inside_its_limits() {
        let value: Value = serde_json::from_str(&hello(
            &"i".repeat(200),
            &"n".repeat(100),
            &"m".repeat(300),
            &"b".repeat(50),
            true,
        ))
        .unwrap();
        assert_eq!(value["type"], "hello");
        assert_eq!(value["relayId"].as_str().unwrap().len(), 128);
        assert_eq!(value["name"].as_str().unwrap().len(), 64);
        assert_eq!(value["model"].as_str().unwrap().len(), 128);
        assert_eq!(value["build"].as_str().unwrap().len(), 32);
        assert_eq!(value["busy"], true);
        assert_eq!(value.as_object().unwrap().len(), 6);
    }

    #[test]
    fn the_small_messages_have_the_hub_shape() {
        let parse = |text: String| serde_json::from_str::<Value>(&text).unwrap();
        assert_eq!(parse(busy(true)), json!({ "type": "busy", "busy": true }));
        assert_eq!(
            parse(token("abc")),
            json!({ "type": "token", "token": "abc" })
        );
        assert_eq!(
            parse(answer("s1", "v=0")),
            json!({ "type": "answer", "sessionId": "s1", "sdp": "v=0" })
        );
        assert_eq!(
            parse(reject("s1", "full")),
            json!({ "type": "reject", "sessionId": "s1", "message": "full" })
        );
    }

    #[test]
    fn a_reject_message_is_never_empty_or_over_the_limit() {
        let value: Value = serde_json::from_str(&reject("s1", "")).unwrap();
        assert!(!value["message"].as_str().unwrap().is_empty());
        let value: Value = serde_json::from_str(&reject("s1", &"x".repeat(900))).unwrap();
        assert_eq!(value["message"].as_str().unwrap().len(), 256);
    }

    #[test]
    fn parses_an_offer_from_the_hub() {
        let text = offer_message(json!({ "iceServers": [{ "urls": ["stun:a.example:3478"] }] }));
        let offer = parse_offer(&text).unwrap();
        assert_eq!(offer.session_id, "s1");
        assert_eq!(offer.sdp, "v=0");
        assert_eq!(offer.ice_servers.len(), 1);
        assert_eq!(offer.ice_servers[0].urls, ["stun:a.example:3478"]);
    }

    #[test]
    fn anything_but_a_good_offer_is_not_an_offer() {
        assert_eq!(parse_offer("pong"), None);
        assert_eq!(parse_offer("not json"), None);
        assert_eq!(parse_offer(r#"{"type":"busy"}"#), None);
        assert_eq!(parse_offer(r#"{"type":"offer","sdp":"v=0"}"#), None);
        assert_eq!(
            parse_offer(r#"{"type":"offer","sessionId":"s","sdp":""}"#),
            None
        );
        let huge = offer_message(json!({ "sdp": "x".repeat(MAX_SDP + 1) }));
        assert_eq!(parse_offer(&huge), None);
    }

    #[test]
    fn an_offer_without_ice_servers_still_parses() {
        assert!(
            parse_offer(&offer_message(json!({})))
                .unwrap()
                .ice_servers
                .is_empty()
        );
        let odd = offer_message(json!({ "iceServers": "nope" }));
        assert!(parse_offer(&odd).unwrap().ice_servers.is_empty());
    }

    #[test]
    fn keeps_stun_and_udp_turn_and_skips_what_webrtc_rs_cannot_use() {
        let servers = json!([
            { "urls": ["stun:stun.cloudflare.com:3478", "stuns:s.example:5349"] },
            {
                "urls": [
                    "turn:turn.example:3478?transport=udp",
                    "turn:turn.example:3478",
                    "turn:turn.example:80?transport=tcp",
                    "turns:turn.example:5349?transport=tcp",
                ],
                "username": "u",
                "credential": "c",
            },
        ]);
        let usable = usable_ice_servers(Some(&servers));
        assert_eq!(usable.len(), 2);
        assert_eq!(usable[0].urls, ["stun:stun.cloudflare.com:3478"]);
        assert_eq!(
            usable[1].urls,
            [
                "turn:turn.example:3478?transport=udp",
                "turn:turn.example:3478"
            ]
        );
        assert_eq!(
            (usable[1].username.as_str(), usable[1].credential.as_str()),
            ("u", "c")
        );
    }

    #[test]
    fn turn_without_credentials_is_skipped_so_the_peer_still_builds() {
        let servers = json!([
            { "urls": ["turn:turn.example:3478"] },
            { "urls": ["turn:turn.example:3478"], "username": "u" },
            { "urls": ["stun:a.example"] },
        ]);
        let usable = usable_ice_servers(Some(&servers));
        assert_eq!(usable.len(), 1);
        assert_eq!(usable[0].urls, ["stun:a.example"]);
    }

    #[test]
    fn a_stun_url_loses_its_query_and_a_string_url_is_accepted() {
        let servers = json!([{ "urls": "stun:a.example:3478?transport=udp" }, { "urls": 5 }]);
        let usable = usable_ice_servers(Some(&servers));
        assert_eq!(usable.len(), 1);
        assert_eq!(usable[0].urls, ["stun:a.example:3478"]);
        assert!(usable_ice_servers(None).is_empty());
    }

    #[test]
    fn malformed_urls_are_dropped() {
        let servers = json!([{ "urls": ["stun:", "nocolon", "http://x.example", ""] }]);
        assert!(usable_ice_servers(Some(&servers)).is_empty());
    }

    #[test]
    fn the_default_servers_are_two_stun_urls() {
        let urls: Vec<String> = default_ice_servers()
            .into_iter()
            .flat_map(|s| s.urls)
            .collect();
        assert_eq!(
            urls,
            [
                "stun:stun.cloudflare.com:3478",
                "stun:stun.l.google.com:19302"
            ]
        );
    }

    #[test]
    fn the_computer_name_is_never_empty() {
        assert!(!computer_name().is_empty());
    }
}
