#![allow(clippy::result_large_err)]

use serde_json::{Value, json};
use spectrum_relay::chat::Ask;
use spectrum_relay::hub::{self, Hub};
use spectrum_relay::p2p::{GenError, Generate, Identity, Link, Options, PeerHost, Timings, serve};
use std::net::TcpListener;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tungstenite::Message;
use tungstenite::handshake::server::{ErrorResponse, Request, Response};
use tungstenite::http::StatusCode;

struct Silent;

impl Generate for Silent {
    fn generate(&self, _: &Ask, _: &mut dyn FnMut(&str) -> bool) -> Result<String, GenError> {
        Err(GenError::Busy)
    }
}

struct Always(AtomicBool);

impl Link for Always {
    fn busy(&self) -> bool {
        self.0.load(std::sync::atomic::Ordering::SeqCst)
    }

    fn model(&self) -> String {
        "scripted".into()
    }

    fn keep_going(&self) -> bool {
        true
    }

    fn fresh_token(&self) -> Result<String, String> {
        Ok("fresh-token".into())
    }
}

fn host() -> PeerHost {
    PeerHost::new(Arc::new(Silent), Options::default(), |_| {}).unwrap()
}

fn text(socket: &mut tungstenite::WebSocket<std::net::TcpStream>) -> String {
    loop {
        match socket.read().unwrap() {
            Message::Text(t) => return t.as_str().to_owned(),
            Message::Close(_) => panic!("closed early"),
            _ => {}
        }
    }
}

#[test]
fn connects_with_the_bearer_token_and_exchanges_text_frames() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("ws://{}/chat/relay", listener.local_addr().unwrap());
    let header = Arc::new(Mutex::new(String::new()));
    let seen = Arc::new(Mutex::new(Vec::<String>::new()));

    let server = std::thread::spawn({
        let (header, seen) = (header.clone(), seen.clone());
        move || {
            let (stream, _) = listener.accept().unwrap();
            let callback = |request: &Request, response: Response| {
                *header.lock().unwrap() = request
                    .headers()
                    .get("authorization")
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or_default()
                    .to_owned();
                assert_eq!(request.uri().path(), "/chat/relay");
                Ok(response)
            };
            let mut socket = tungstenite::accept_hdr(stream, callback).unwrap();
            seen.lock().unwrap().push(text(&mut socket));
            let offer = json!({
                "type": "offer", "sessionId": "s1", "sdp": "not an sdp", "iceServers": []
            });
            socket.send(Message::text(offer.to_string())).unwrap();
            socket.send(Message::text("pong")).unwrap();

            for _ in 0..3 {
                seen.lock().unwrap().push(text(&mut socket));
            }
            socket.close(None).unwrap();
            let _ = socket.flush();
            while socket.read().is_ok() {}
        }
    });

    let mut client = hub::connect(&url, "abc.def.ghi").unwrap();
    let who = Identity {
        relay_id: "r1".into(),
        name: "Shop".into(),
        build: "dev".into(),
    };
    let timings = Timings {
        tick: Duration::from_millis(20),
        ping: Duration::from_millis(50),
        token: Duration::from_millis(50),
        quiet: Duration::from_secs(60),
    };
    let result = serve(
        &host(),
        &mut client,
        &Always(AtomicBool::new(false)),
        &who,
        &timings,
    );
    server.join().unwrap();

    assert_eq!(result.unwrap_err(), "the hub closed the connection");
    assert_eq!(*header.lock().unwrap(), "Bearer abc.def.ghi");
    let seen: Vec<Value> = seen
        .lock()
        .unwrap()
        .iter()
        .map(|m| serde_json::from_str(m).unwrap_or(Value::String(m.clone())))
        .collect();
    assert_eq!(seen[0]["type"], "hello");
    assert_eq!(seen[0]["relayId"], "r1");
    assert!(
        seen.iter()
            .any(|m| m["type"] == "reject" && m["sessionId"] == "s1")
    );
    assert!(seen.iter().any(|m| m == "ping"));
    assert!(
        seen.iter()
            .any(|m| m["type"] == "token" && m["token"] == "fresh-token")
    );
}

#[test]
fn recv_returns_none_when_the_hub_is_quiet() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("ws://{}/chat/relay", listener.local_addr().unwrap());
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut socket = tungstenite::accept(stream).unwrap();
        std::thread::sleep(Duration::from_millis(300));
        socket.send(Message::text("late")).unwrap();
        let _ = socket.read();
    });
    let mut client = hub::connect(&url, "t").unwrap();
    assert_eq!(client.recv(Duration::from_millis(50)).unwrap(), None);
    let mut message = None;
    for _ in 0..40 {
        message = client.recv(Duration::from_millis(50)).unwrap();
        if message.is_some() {
            break;
        }
    }
    assert_eq!(message.as_deref(), Some("late"));
    client.close();
    server.join().unwrap();
}

#[test]
fn a_refused_account_gets_a_message_that_names_the_fix() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("ws://{}/chat/relay", listener.local_addr().unwrap());
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let callback = |_: &Request, _: Response| {
            let mut refusal = ErrorResponse::new(Some("Unauthorized".into()));
            *refusal.status_mut() = StatusCode::UNAUTHORIZED;
            Err(refusal)
        };
        assert!(tungstenite::accept_hdr(stream, callback).is_err());
    });
    let error = hub::connect(&url, "t").err().unwrap();
    server.join().unwrap();
    assert!(error.contains("401"), "{error}");
    assert!(error.contains("appConfig/relay.uids"), "{error}");
}

#[test]
fn an_unreachable_hub_is_an_error_not_a_hang() {
    let port = TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port();
    let error = hub::connect(&format!("ws://127.0.0.1:{port}/chat/relay"), "t")
        .err()
        .unwrap();
    assert!(error.contains("could not connect"), "{error}");
}
