use rtc::peer_connection::configuration::setting_engine::{
    SctpMaxMessageSize, SettingEngineBuilder,
};
use serde_json::{Value, json};
use spectrum_relay::chat::Ask;
use spectrum_relay::hub::Hub;
use spectrum_relay::p2p::{
    GenError, Generate, Identity, Link, Options, PeerHost, Timings, reply_to_offer, serve,
};
use spectrum_relay::signaling;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::mpsc as std_mpsc;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::timeout;
use webrtc::data_channel::{DataChannel, DataChannelEvent};
use webrtc::peer_connection::{
    PeerConnection, PeerConnectionBuilder, PeerConnectionEventHandler, RTCConfigurationBuilder,
    RTCIceGatheringState, RTCSessionDescription,
};

const WAIT: Duration = Duration::from_secs(15);

#[derive(Clone)]
enum Script {
    Reply(Vec<&'static str>),

    Endless,
}

struct Scripted {
    script: Mutex<Script>,
    active: AtomicBool,
    stopped: AtomicBool,
    prompt_chars: AtomicUsize,
}

impl Scripted {
    fn new(script: Script) -> Arc<Self> {
        Arc::new(Self {
            script: Mutex::new(script),
            active: AtomicBool::new(false),
            stopped: AtomicBool::new(false),
            prompt_chars: AtomicUsize::new(0),
        })
    }
}

impl Generate for Scripted {
    fn generate(&self, ask: &Ask, emit: &mut dyn FnMut(&str) -> bool) -> Result<String, GenError> {
        if self.active.swap(true, Ordering::SeqCst) {
            return Err(GenError::Busy);
        }
        self.stopped.store(false, Ordering::SeqCst);
        self.prompt_chars
            .store(ask.prompt.chars().count(), Ordering::SeqCst);
        let script = self.script.lock().unwrap().clone();
        match script {
            Script::Reply(pieces) => {
                for piece in pieces {
                    if !emit(piece) {
                        break;
                    }
                }
            }
            Script::Endless => {
                let mut kept_going = emit("Team 3847 is a strong pick for second seat. ");
                while kept_going {
                    std::thread::sleep(Duration::from_millis(20));
                    kept_going = emit("More. ");
                }
                self.stopped.store(true, Ordering::SeqCst);
            }
        }
        self.active.store(false, Ordering::SeqCst);
        Ok("scripted".into())
    }
}

struct Gathering(mpsc::Sender<()>);

#[async_trait::async_trait]
impl PeerConnectionEventHandler for Gathering {
    async fn on_ice_gathering_state_change(&self, state: RTCIceGatheringState) {
        if state == RTCIceGatheringState::Complete {
            let _ = self.0.try_send(());
        }
    }
}

fn options() -> Options {
    Options {
        ice_servers: vec![],
        udp_addrs: vec!["127.0.0.1:0".into()],
        ..Options::default()
    }
}

fn host(generate: Arc<Scripted>) -> Arc<PeerHost> {
    Arc::new(PeerHost::new(generate, options(), |_| {}).unwrap())
}

struct Browser {
    _peer: Arc<dyn PeerConnection>,
    channel: Arc<dyn DataChannel>,
}

fn offer_message(session_id: &str, sdp: &str) -> String {
    offer_with_servers(session_id, sdp, json!([]))
}

fn offer_with_servers(session_id: &str, sdp: &str, ice_servers: Value) -> String {
    json!({ "type": "offer", "sessionId": session_id, "sdp": sdp, "iceServers": ice_servers })
        .to_string()
}

fn answer_sdp(reply: &str, session_id: &str) -> String {
    let reply: Value = serde_json::from_str(reply).unwrap();
    assert_eq!(reply["type"], "answer", "{reply}");
    assert_eq!(reply["sessionId"], session_id);
    reply["sdp"].as_str().unwrap().to_owned()
}

impl Browser {

    async fn connect(host: &Arc<PeerHost>) -> Self {
        Self::connect_via(|offer_sdp| {
            let host = host.clone();
            async move {
                tokio::task::spawn_blocking(move || {
                    let offer = signaling::parse_offer(&offer_message("s1", &offer_sdp)).unwrap();
                    answer_sdp(&reply_to_offer(&host, &offer), "s1")
                })
                .await
                .unwrap()
            }
        })
        .await
    }

    async fn connect_via<F, Fut>(relay: F) -> Self
    where
        F: FnOnce(String) -> Fut,
        Fut: std::future::Future<Output = String>,
    {
        let (gathered_tx, mut gathered_rx) = mpsc::channel(1);
        let peer = PeerConnectionBuilder::new()
            .with_configuration(RTCConfigurationBuilder::new().build())

            .with_setting_engine(
                SettingEngineBuilder::new()
                    .with_sctp_max_message_size(SctpMaxMessageSize::Bounded(256 * 1024))
                    .build(),
            )
            .with_handler(Arc::new(Gathering(gathered_tx)))
            .with_udp_addrs(vec!["127.0.0.1:0".to_string()])
            .build()
            .await
            .unwrap();
        let peer: Arc<dyn PeerConnection> = Arc::new(peer);
        let channel = peer.create_data_channel("chat", None).await.unwrap();
        let offer = peer.create_offer(None).await.unwrap();
        peer.set_local_description(offer).await.unwrap();
        timeout(WAIT, gathered_rx.recv()).await.unwrap();
        let offer_sdp = peer.local_description().await.unwrap().sdp;

        let answer = relay(offer_sdp).await;
        peer.set_remote_description(RTCSessionDescription::answer(answer).unwrap())
            .await
            .unwrap();
        loop {
            let event = timeout(WAIT, channel.poll())
                .await
                .expect("the channel never opened");
            if let Some(DataChannelEvent::OnOpen) = event {
                break;
            }
        }
        Self {
            _peer: peer,
            channel,
        }
    }

    async fn send(&self, message: Value) {
        self.channel.send_text(&message.to_string()).await.unwrap();
    }

    async fn next(&self) -> Value {
        loop {
            let event = timeout(WAIT, self.channel.poll())
                .await
                .expect("no message arrived");
            if let Some(DataChannelEvent::OnMessage(message)) = event {
                return serde_json::from_slice(&message.data).unwrap();
            }
        }
    }

    async fn until_finished(&self, id: &str) -> Vec<Value> {
        let mut messages = Vec::new();
        loop {
            let message = self.next().await;
            assert_eq!(message["id"], id);
            let finished = message["type"] != "chunk";
            messages.push(message);
            if finished {
                return messages;
            }
        }
    }
}

fn ask(id: &str, prompt: &str) -> Value {
    json!({ "type": "ask", "id": id, "system": "Be brief.", "prompt": prompt, "maxTokens": 256 })
}

fn run(test: impl std::future::Future<Output = ()>) {
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(test);
}

#[test]
fn streams_an_answer_and_takes_a_large_prompt() {
    let model = Scripted::new(Script::Reply(vec![
        "Team 3847 ",
        "is a strong ",
        "pick for second ",
        "seat.",
    ]));
    let host = host(model.clone());
    run(async {
        let browser = Browser::connect(&host).await;
        browser.send(ask("a1", &"x".repeat(150_000))).await;
        let messages = browser.until_finished("a1").await;

        let text: String = messages
            .iter()
            .filter(|m| m["type"] == "chunk")
            .map(|m| m["text"].as_str().unwrap())
            .collect();
        assert_eq!(text, "Team 3847 is a strong pick for second seat.");
        let last = messages.last().unwrap();
        assert_eq!(last["type"], "done");
        assert_eq!(last["model"], "scripted");
        assert_eq!(model.prompt_chars.load(Ordering::SeqCst), 150_000);
        assert_eq!(host.open_peers(), 1);

        browser.send(ask("a2", "again?")).await;
        let second = browser.until_finished("a2").await;
        assert_eq!(second.last().unwrap()["type"], "done");
    });
}

#[test]
fn refuses_a_refusal_before_sending_any_of_it() {
    let host = host(Scripted::new(Script::Reply(vec![
        "I cannot help ",
        "with that request.",
    ])));
    run(async {
        let browser = Browser::connect(&host).await;
        browser.send(ask("a1", "who?")).await;
        let messages = browser.until_finished("a1").await;
        assert_eq!(messages.len(), 1, "{messages:?}");
        assert_eq!(messages[0]["type"], "error");
        assert_eq!(messages[0]["message"], "the model did not give an answer");
    });
}

#[test]
fn rejects_a_bad_ask_by_name() {
    let host = host(Scripted::new(Script::Reply(vec![])));
    run(async {
        let browser = Browser::connect(&host).await;
        browser
            .send(json!({ "type": "ask", "id": "a1", "prompt": "" }))
            .await;
        let messages = browser.until_finished("a1").await;
        assert_eq!(messages[0]["type"], "error");
        assert_eq!(messages[0]["message"], "the prompt is empty");
        browser
            .send(json!({ "type": "ask", "id": "a2", "prompt": "x", "maxTokens": 9999 }))
            .await;
        let messages = browser.until_finished("a2").await;
        assert_eq!(messages[0]["message"], "maxTokens is out of range");
    });
}

#[test]
fn answers_one_ask_at_a_time_and_stops_on_cancel() {
    let model = Scripted::new(Script::Endless);
    let host = host(model.clone());
    run(async {
        let first = Browser::connect(&host).await;
        let second = Browser::connect(&host).await;

        first.send(ask("a1", "go on")).await;
        let opening = first.next().await;
        assert_eq!(opening["type"], "chunk");

        first.send(ask("a2", "also")).await;
        second.send(ask("b1", "me too")).await;
        let busy_here = loop {
            let message = first.next().await;
            if message["id"] == "a2" {
                break message;
            }
        };
        assert_eq!(busy_here["type"], "error");
        assert_eq!(busy_here["message"], "busy");
        let busy_there = second.until_finished("b1").await;
        assert_eq!(busy_there[0]["message"], "busy");

        first.send(json!({ "type": "cancel", "id": "a1" })).await;
        let deadline = std::time::Instant::now() + WAIT;
        while !model.stopped.load(Ordering::SeqCst) {
            assert!(
                std::time::Instant::now() < deadline,
                "generation never stopped"
            );
            tokio::time::sleep(Duration::from_millis(20)).await;
        }

        *model.script.lock().unwrap() = Script::Reply(vec!["Team 254 is fast at the end."]);
        tokio::time::sleep(Duration::from_millis(300)).await;
        first.send(ask("a3", "after the cancel")).await;

        let messages = loop {
            let message = first.next().await;
            if message["id"] == "a3" {
                break message;
            }
            assert_eq!(message["id"], "a1");
            assert_eq!(message["type"], "chunk");
        };
        assert_eq!(messages["type"], "chunk");
    });
}

struct ChannelHub {
    from_hub: std_mpsc::Receiver<String>,
    to_hub: std_mpsc::Sender<String>,
}

impl Hub for ChannelHub {
    fn send(&mut self, text: &str) -> Result<(), String> {
        self.to_hub.send(text.into()).map_err(|e| e.to_string())
    }

    fn recv(&mut self, wait: Duration) -> Result<Option<String>, String> {
        match self.from_hub.recv_timeout(wait) {
            Ok(text) => Ok(Some(text)),
            Err(std_mpsc::RecvTimeoutError::Timeout) => Ok(None),
            Err(std_mpsc::RecvTimeoutError::Disconnected) => Err("the hub went away".into()),
        }
    }

    fn close(&mut self) {}
}

struct RunningLink(Arc<AtomicBool>);

impl Link for RunningLink {
    fn busy(&self) -> bool {
        false
    }

    fn model(&self) -> String {
        "scripted".into()
    }

    fn keep_going(&self) -> bool {
        !self.0.load(Ordering::SeqCst)
    }

    fn fresh_token(&self) -> Result<String, String> {
        Ok("token".into())
    }
}

#[test]
fn serves_a_chat_that_arrives_as_a_hub_offer() {
    let model = Scripted::new(Script::Reply(vec!["Team 3847 is a strong pick."]));
    let host = Arc::new(PeerHost::new(model, options(), |_| {}).unwrap());
    let (to_relay, from_hub) = std_mpsc::channel();
    let (to_hub, from_relay) = std_mpsc::channel();
    let stop = Arc::new(AtomicBool::new(false));
    let relay = std::thread::spawn({
        let (host, stop) = (host.clone(), stop.clone());
        move || {
            let mut hub = ChannelHub { from_hub, to_hub };
            let who = Identity {
                relay_id: "r1".into(),
                name: "Shop".into(),
                build: "dev".into(),
            };
            let timings = Timings {
                tick: Duration::from_millis(20),
                ..Timings::default()
            };
            serve(&host, &mut hub, &RunningLink(stop), &who, &timings)
        }
    });

    let hello: Value = serde_json::from_str(&from_relay.recv_timeout(WAIT).unwrap()).unwrap();
    assert_eq!(hello["type"], "hello");
    assert_eq!(hello["relayId"], "r1");

    let offers = to_relay.clone();
    run(async {
        let browser = Browser::connect_via(|offer_sdp| async move {
            offers.send(offer_message("s9", &offer_sdp)).unwrap();
            let reply = tokio::task::spawn_blocking(move || from_relay.recv_timeout(WAIT).unwrap())
                .await
                .unwrap();
            answer_sdp(&reply, "s9")
        })
        .await;
        browser.send(ask("a1", "who?")).await;
        let messages = browser.until_finished("a1").await;
        assert_eq!(messages.last().unwrap()["type"], "done");
        assert_eq!(host.open_peers(), 1);
    });

    stop.store(true, Ordering::SeqCst);
    assert!(relay.join().unwrap().is_ok());
    drop(to_relay);
}

#[test]
fn answers_an_offer_that_carries_stun_and_turn_servers() {
    let model = Scripted::new(Script::Reply(vec!["Team 254 is fast at the end."]));
    let options = Options {
        gather_timeout: Duration::from_millis(500),
        ..options()
    };
    let host = Arc::new(PeerHost::new(model, options, |_| {}).unwrap());

    let servers = json!([
        { "urls": ["stun:127.0.0.1:9?transport=udp"] },
        {
            "urls": [
                "turn:127.0.0.1:9?transport=udp",
                "turn:127.0.0.1:9?transport=tcp",
                "turns:127.0.0.1:9?transport=tcp",
            ],
            "username": "user",
            "credential": "pass",
        },
    ]);
    run(async {
        let browser = Browser::connect_via(|offer_sdp| {
            let host = host.clone();
            async move {
                tokio::task::spawn_blocking(move || {
                    let text = offer_with_servers("s2", &offer_sdp, servers);
                    let offer = signaling::parse_offer(&text).unwrap();
                    assert_eq!(offer.ice_servers.len(), 2);
                    answer_sdp(&reply_to_offer(&host, &offer), "s2")
                })
                .await
                .unwrap()
            }
        })
        .await;
        browser.send(ask("a1", "who?")).await;
        let messages = browser.until_finished("a1").await;
        assert_eq!(messages.last().unwrap()["type"], "done");
    });
}
