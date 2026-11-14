use crate::auth::{self, StoredToken};
use crate::chat::{self, Ask, CHANNEL_LABEL, Gate, Incoming, OpeningGate};
use crate::firebase_config::CHAT_HUB_URL;
use crate::hub::{self, Hub};
use crate::llama;
use crate::service::{ModelError, Shared};
use crate::signaling::{self, IceServer, MAX_SDP, Offer};
use crate::update;
use rtc::peer_connection::configuration::setting_engine::{
    SctpMaxMessageSize, SettingEngineBuilder,
};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use webrtc::data_channel::{DataChannel, DataChannelEvent};
use webrtc::peer_connection::{
    PeerConnection, PeerConnectionBuilder, PeerConnectionEventHandler, RTCConfigurationBuilder,
    RTCIceGatheringState, RTCIceServer, RTCPeerConnectionState, RTCSessionDescription,
};

const GATHER_TIMEOUT: Duration = Duration::from_secs(5);

const OPEN_TIMEOUT: Duration = Duration::from_secs(30);
const IDLE_TIMEOUT: Duration = Duration::from_secs(10 * 60);

const MAX_PEERS: usize = 4;

const MAX_MESSAGE_BYTES: u32 = 256 * 1024;
const TICK: Duration = Duration::from_millis(500);
const BACKOFF_FIRST: Duration = Duration::from_secs(1);
const BACKOFF_MAX: Duration = Duration::from_secs(60);

const STABLE: Duration = Duration::from_secs(60);
const IDLE_PAUSE: Duration = Duration::from_secs(2);

pub enum GenError {

    Busy,
    Failed(String),
}

pub trait Generate: Send + Sync + 'static {

    fn generate(&self, ask: &Ask, emit: &mut dyn FnMut(&str) -> bool) -> Result<String, GenError>;
}

pub struct LlamaGenerator {
    pub shared: Arc<Shared>,
}

impl Generate for LlamaGenerator {
    fn generate(&self, ask: &Ask, emit: &mut dyn FnMut(&str) -> bool) -> Result<String, GenError> {
        let model = self.shared.config().model.name;
        self.shared
            .with_model(false, |server| {
                llama::chat_stream(
                    &server.url,
                    &model,
                    ask.system.as_deref(),
                    &ask.prompt,
                    ask.max_tokens,
                    emit,
                )
            })
            .map(|()| model)
            .map_err(|e| match e {
                ModelError::Busy => GenError::Busy,
                ModelError::Failed(message) => GenError::Failed(message),
            })
    }
}

#[derive(Clone)]
pub struct Options {

    pub ice_servers: Vec<IceServer>,
    pub udp_addrs: Vec<String>,
    pub gather_timeout: Duration,
    pub open_timeout: Duration,
    pub idle_timeout: Duration,
    pub max_peers: usize,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            ice_servers: signaling::default_ice_servers(),
            udp_addrs: vec!["0.0.0.0:0".into()],
            gather_timeout: GATHER_TIMEOUT,
            open_timeout: OPEN_TIMEOUT,
            idle_timeout: IDLE_TIMEOUT,
            max_peers: MAX_PEERS,
        }
    }
}

struct Inner {
    generate: Arc<dyn Generate>,
    options: Options,
    live: AtomicUsize,
    open: AtomicUsize,
    on_open_peers: Box<dyn Fn(usize) + Send + Sync>,
}

impl Inner {
    fn channel_opened(&self) {
        let open = self.open.fetch_add(1, Ordering::SeqCst) + 1;
        (self.on_open_peers)(open);
    }

    fn channel_closed(&self) {
        let open = self.open.fetch_sub(1, Ordering::SeqCst) - 1;
        (self.on_open_peers)(open);
    }
}

pub struct PeerHost {
    runtime: tokio::runtime::Runtime,
    inner: Arc<Inner>,
}

impl PeerHost {

    pub fn new(
        generate: Arc<dyn Generate>,
        options: Options,
        on_open_peers: impl Fn(usize) + Send + Sync + 'static,
    ) -> Result<Self, String> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("relay-rtc")
            .enable_all()
            .build()
            .map_err(|e| format!("could not start the WebRTC runtime: {e}"))?;
        Ok(Self {
            runtime,
            inner: Arc::new(Inner {
                generate,
                options,
                live: AtomicUsize::new(0),
                open: AtomicUsize::new(0),
                on_open_peers: Box::new(on_open_peers),
            }),
        })
    }

    pub fn answer(&self, offer: &str, ice_servers: &[IceServer]) -> Result<String, String> {
        let servers = if ice_servers.is_empty() {
            self.inner.options.ice_servers.clone()
        } else {
            ice_servers.to_vec()
        };
        self.runtime
            .block_on(answer_offer(self.inner.clone(), offer.to_owned(), servers))
    }

    pub fn open_peers(&self) -> usize {
        self.inner.open.load(Ordering::SeqCst)
    }
}

struct Handler {
    inner: Arc<Inner>,
    gathered: mpsc::Sender<()>,
    opened: mpsc::Sender<()>,
    closed: mpsc::Sender<()>,
}

#[async_trait::async_trait]
impl PeerConnectionEventHandler for Handler {
    async fn on_ice_gathering_state_change(&self, state: RTCIceGatheringState) {
        if state == RTCIceGatheringState::Complete {
            let _ = self.gathered.try_send(());
        }
    }

    async fn on_connection_state_change(&self, state: RTCPeerConnectionState) {
        if matches!(
            state,
            RTCPeerConnectionState::Failed | RTCPeerConnectionState::Closed
        ) {
            let _ = self.closed.try_send(());
        }
    }

    async fn on_data_channel(&self, channel: Arc<dyn DataChannel>) {

        tokio::spawn(serve_channel(
            self.inner.clone(),
            channel,
            self.opened.clone(),
            self.closed.clone(),
        ));
    }
}

async fn answer_offer(
    inner: Arc<Inner>,
    offer: String,
    servers: Vec<IceServer>,
) -> Result<String, String> {
    if inner.live.load(Ordering::SeqCst) >= inner.options.max_peers {
        return Err(format!("already serving {} chats", inner.options.max_peers));
    }
    let offer = RTCSessionDescription::offer(offer).map_err(|e| format!("bad offer: {e}"))?;
    let (gathered_tx, mut gathered_rx) = mpsc::channel(1);
    let (opened_tx, opened_rx) = mpsc::channel(1);
    let (closed_tx, closed_rx) = mpsc::channel(1);
    let handler = Handler {
        inner: inner.clone(),
        gathered: gathered_tx,
        opened: opened_tx,
        closed: closed_tx,
    };
    let ice_servers = servers
        .into_iter()
        .map(|server| RTCIceServer {
            urls: server.urls,
            username: server.username,
            credential: server.credential,
        })
        .collect();
    let peer = PeerConnectionBuilder::new()
        .with_configuration(
            RTCConfigurationBuilder::new()
                .with_ice_servers(ice_servers)
                .build(),
        )
        .with_setting_engine(
            SettingEngineBuilder::new()
                .with_sctp_max_message_size(SctpMaxMessageSize::Bounded(MAX_MESSAGE_BYTES))
                .build(),
        )
        .with_handler(Arc::new(handler))
        .with_udp_addrs(inner.options.udp_addrs.clone())
        .build()
        .await
        .map_err(|e| format!("could not start a peer: {e}"))?;
    let peer: Arc<dyn PeerConnection> = Arc::new(peer);
    inner.live.fetch_add(1, Ordering::SeqCst);

    match negotiate(&inner, &peer, offer, &mut gathered_rx).await {
        Ok(answer) => {
            tokio::spawn(supervise(inner, peer, opened_rx, closed_rx));
            Ok(answer)
        }
        Err(e) => {
            let _ = peer.close().await;
            inner.live.fetch_sub(1, Ordering::SeqCst);
            Err(e)
        }
    }
}

async fn negotiate(
    inner: &Inner,
    peer: &Arc<dyn PeerConnection>,
    offer: RTCSessionDescription,
    gathered: &mut mpsc::Receiver<()>,
) -> Result<String, String> {
    let err = |what: &str| {
        let what = what.to_owned();
        move |e: webrtc::error::Error| format!("{what}: {e}")
    };
    peer.set_remote_description(offer)
        .await
        .map_err(err("could not apply the offer"))?;
    let answer = peer
        .create_answer(None)
        .await
        .map_err(err("could not create an answer"))?;
    peer.set_local_description(answer)
        .await
        .map_err(err("could not apply the answer"))?;
    let _ = tokio::time::timeout(inner.options.gather_timeout, gathered.recv()).await;
    let local = peer
        .local_description()
        .await
        .ok_or("the peer has no local description")?;
    if local.sdp.len() > MAX_SDP {
        return Err("the answer is too large to write".into());
    }
    Ok(local.sdp)
}

async fn supervise(
    inner: Arc<Inner>,
    peer: Arc<dyn PeerConnection>,
    mut opened: mpsc::Receiver<()>,
    mut closed: mpsc::Receiver<()>,
) {
    tokio::select! {
        _ = opened.recv() => {
            closed.recv().await;
        }
        _ = closed.recv() => {}
        _ = tokio::time::sleep(inner.options.open_timeout) => {}
    }
    let _ = peer.close().await;
    inner.live.fetch_sub(1, Ordering::SeqCst);
}

struct Running {
    id: String,
    cancel: Arc<AtomicBool>,
    finished: Arc<AtomicBool>,
}

async fn serve_channel(
    inner: Arc<Inner>,
    channel: Arc<dyn DataChannel>,
    opened: mpsc::Sender<()>,
    closed: mpsc::Sender<()>,
) {
    if channel.label().await.unwrap_or_default() != CHANNEL_LABEL {
        let _ = channel.close().await;
        let _ = closed.try_send(());
        return;
    }
    let (out_tx, mut out_rx) = mpsc::unbounded_channel::<String>();
    let mut current: Option<Running> = None;
    let mut counted = false;
    let idle = tokio::time::sleep(inner.options.idle_timeout);
    tokio::pin!(idle);
    loop {
        tokio::select! {
            event = channel.poll() => match event {
                Some(DataChannelEvent::OnOpen) if !counted => {
                    counted = true;
                    inner.channel_opened();
                    let _ = opened.try_send(());
                }
                Some(DataChannelEvent::OnMessage(message)) => {
                    idle.as_mut().reset(tokio::time::Instant::now() + inner.options.idle_timeout);
                    let text = String::from_utf8_lossy(&message.data).into_owned();
                    handle_message(&inner, &out_tx, &mut current, &text);
                }
                Some(DataChannelEvent::OnClose) | None => break,
                Some(_) => {}
            },
            Some(text) = out_rx.recv() => {
                idle.as_mut().reset(tokio::time::Instant::now() + inner.options.idle_timeout);
                if channel.send_text(&text).await.is_err() {
                    break;
                }
            }
            () = &mut idle => break,
        }
    }
    if let Some(running) = &current {
        running.cancel.store(true, Ordering::SeqCst);
    }
    if counted {
        inner.channel_closed();
    }
    let _ = channel.close().await;
    let _ = closed.try_send(());
}

fn handle_message(
    inner: &Arc<Inner>,
    out: &mpsc::UnboundedSender<String>,
    current: &mut Option<Running>,
    text: &str,
) {
    match chat::parse_incoming(text) {
        Incoming::Ask(ask) => {
            if current
                .as_ref()
                .is_some_and(|r| !r.finished.load(Ordering::SeqCst))
            {
                let _ = out.send(chat::error(&ask.id, "busy"));
                return;
            }
            let running = Running {
                id: ask.id.clone(),
                cancel: Arc::new(AtomicBool::new(false)),
                finished: Arc::new(AtomicBool::new(false)),
            };
            let (cancel, finished) = (running.cancel.clone(), running.finished.clone());
            *current = Some(running);
            let (generate, out) = (inner.generate.clone(), out.clone());

            tokio::task::spawn_blocking(move || {
                run_ask(generate.as_ref(), &ask, &out, &cancel);
                finished.store(true, Ordering::SeqCst);
            });
        }
        Incoming::Cancel(id) => {
            if let Some(running) = current.as_ref().filter(|r| r.id == id) {
                running.cancel.store(true, Ordering::SeqCst);
            }
        }
        Incoming::Rejected {
            id: Some(id),
            reason,
        } => {
            let _ = out.send(chat::error(&id, &reason));
        }
        Incoming::Rejected { id: None, .. } => {}
    }
}

const NO_ANSWER: &str = "the model did not give an answer";

fn run_ask(
    generate: &dyn Generate,
    ask: &Ask,
    out: &mpsc::UnboundedSender<String>,
    cancel: &AtomicBool,
) {
    let mut gate = OpeningGate::default();
    let mut refused = false;
    let result = generate.generate(ask, &mut |piece| {
        if cancel.load(Ordering::SeqCst) {
            return false;
        }
        match gate.push(piece) {
            Gate::Hold => true,
            Gate::Send(text) => out.send(chat::chunk(&ask.id, &text)).is_ok(),
            Gate::Refused => {
                refused = true;
                false
            }
        }
    });
    if cancel.load(Ordering::SeqCst) {
        return;
    }
    let reply = match result {
        _ if refused => chat::error(&ask.id, NO_ANSWER),
        Err(GenError::Busy) => chat::error(&ask.id, "busy"),
        Err(GenError::Failed(message)) => chat::error(&ask.id, &message),
        Ok(model) => match gate.finish() {
            Gate::Send(rest) => {
                if !rest.is_empty() {
                    let _ = out.send(chat::chunk(&ask.id, &rest));
                }
                chat::done(&ask.id, &model)
            }
            Gate::Hold | Gate::Refused => chat::error(&ask.id, NO_ANSWER),
        },
    };
    let _ = out.send(reply);
}

pub fn reply_to_offer(host: &PeerHost, offer: &Offer) -> String {

    let answered = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        host.answer(&offer.sdp, &offer.ice_servers)
    }))
    .unwrap_or_else(|_| Err("could not answer the offer".into()));
    match answered {
        Ok(sdp) => signaling::answer(&offer.session_id, &sdp),
        Err(e) => signaling::reject(&offer.session_id, &e),
    }
}

pub trait Link {

    fn busy(&self) -> bool;
    fn model(&self) -> String;
    fn keep_going(&self) -> bool;
    fn fresh_token(&self) -> Result<String, String>;
}

pub struct Identity {
    pub relay_id: String,
    pub name: String,
    pub build: String,
}

pub struct Timings {
    pub tick: Duration,
    pub ping: Duration,
    pub token: Duration,

    pub quiet: Duration,
}

impl Default for Timings {
    fn default() -> Self {
        Self {
            tick: TICK,
            ping: signaling::PING_EVERY,
            token: signaling::TOKEN_EVERY,
            quiet: signaling::PING_EVERY * 3,
        }
    }
}

pub fn serve(
    host: &PeerHost,
    hub: &mut dyn Hub,
    link: &dyn Link,
    who: &Identity,
    timings: &Timings,
) -> Result<(), String> {
    let mut busy = link.busy();
    let mut model = link.model();
    hub.send(&signaling::hello(
        &who.relay_id,
        &who.name,
        &model,
        &who.build,
        busy,
    ))?;
    let (mut last_ping, mut last_token) = (Instant::now(), Instant::now());
    let mut last_heard = Instant::now();
    while link.keep_going() {
        if let Some(text) = hub.recv(timings.tick)? {
            last_heard = Instant::now();
            if let Some(offer) = signaling::parse_offer(&text) {
                hub.send(&reply_to_offer(host, &offer))?;
            }
        } else if last_heard.elapsed() >= timings.quiet {
            return Err("the hub went quiet".into());
        }
        let (now_busy, now_model) = (link.busy(), link.model());
        if now_model != model {
            model = now_model;
            busy = now_busy;
            hub.send(&signaling::hello(
                &who.relay_id,
                &who.name,
                &model,
                &who.build,
                busy,
            ))?;
        } else if now_busy != busy {
            busy = now_busy;
            hub.send(&signaling::busy(busy))?;
        }
        if last_ping.elapsed() >= timings.ping {
            hub.send(signaling::PING)?;
            last_ping = Instant::now();
        }
        if last_token.elapsed() >= timings.token {
            hub.send(&signaling::token(&link.fresh_token()?))?;
            last_token = Instant::now();
        }
    }
    hub.close();
    Ok(())
}

struct ProcessLink<'a>(&'a Shared);

impl Link for ProcessLink<'_> {
    fn busy(&self) -> bool {
        self.0.ready().is_none() || self.0.is_generating()
    }

    fn model(&self) -> String {
        self.0.config().model.name
    }

    fn keep_going(&self) -> bool {
        !self.0.restart_requested()
            && self.0.config().enabled
            && auth::load_token(&self.0.dirs.token_file()).is_some()
    }

    fn fresh_token(&self) -> Result<String, String> {
        id_token(self.0).map(|(_, token)| token)
    }
}

fn id_token(shared: &Shared) -> Result<(StoredToken, String), String> {
    let stored = auth::load_token(&shared.dirs.token_file()).ok_or("not signed in")?;
    let token = shared.id_token(&stored).map_err(|e| e.to_string())?;
    Ok((stored, token))
}

pub fn spawn(shared: Arc<Shared>) {
    let spawned = std::thread::Builder::new()
        .name("relay-chat".into())
        .spawn({
            let shared = shared.clone();
            move || run(&shared)
        });
    if let Err(e) = spawned {
        shared.chat_error(format!("could not start the chat thread: {e}"));
    }
}

struct Backoff(Duration);

impl Backoff {
    fn new() -> Self {
        Self(BACKOFF_FIRST)
    }

    fn take(&mut self) -> Duration {
        let wait = self.0;
        self.0 = (wait * 2).min(BACKOFF_MAX);
        wait
    }

    fn reset(&mut self) {
        self.0 = BACKOFF_FIRST;
    }
}

fn pause(shared: &Shared, total: Duration) {
    let end = Instant::now() + total;
    while !shared.restart_requested() {
        let left = end.saturating_duration_since(Instant::now());
        if left.is_zero() {
            break;
        }
        std::thread::sleep(left.min(TICK));
    }
}

fn run(shared: &Arc<Shared>) {
    let generate = Arc::new(LlamaGenerator {
        shared: shared.clone(),
    });
    let reporter = shared.clone();
    let host = match PeerHost::new(generate, Options::default(), move |peers| {
        reporter.update_state(|s| s.chat_peers = peers)
    }) {
        Ok(host) => host,
        Err(e) => return shared.chat_error(e),
    };
    let mut backoff = Backoff::new();
    while !shared.restart_requested() {
        let started = Instant::now();
        let result = connected(shared, &host);
        shared.update_state(|s| s.chat_online = false);
        match result {
            Ok(false) => {
                backoff.reset();
                pause(shared, IDLE_PAUSE);
            }
            Ok(true) => {}
            Err(e) => {
                shared.chat_error(e);
                if started.elapsed() >= STABLE {
                    backoff.reset();
                }
                pause(shared, backoff.take());
            }
        }
    }
}

fn connected(shared: &Arc<Shared>, host: &PeerHost) -> Result<bool, String> {
    let link = ProcessLink(shared);
    if !link.keep_going() {
        return Ok(false);
    }
    let (_, token) = id_token(shared)?;
    let mut socket = hub::connect(CHAT_HUB_URL, &token)?;
    shared.update_state(|s| s.chat_online = true);
    let who = Identity {
        relay_id: shared.config().relay_id,
        name: signaling::computer_name(),
        build: update::BUILD.unwrap_or("dev").into(),
    };
    serve(host, &mut socket, &link, &who, &Timings::default())?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;
    use std::sync::Mutex;

    struct Silent;

    impl Generate for Silent {
        fn generate(&self, _: &Ask, _: &mut dyn FnMut(&str) -> bool) -> Result<String, GenError> {
            Err(GenError::Busy)
        }
    }

    fn host() -> PeerHost {
        PeerHost::new(Arc::new(Silent), Options::default(), |_| {}).unwrap()
    }

    struct FakeHub {
        script: VecDeque<Option<String>>,
        sent: Arc<Mutex<Vec<String>>>,
        closed: Arc<AtomicBool>,
        on_recv: Box<dyn FnMut(usize) + Send>,
        reads: usize,
    }

    impl FakeHub {
        fn new(script: Vec<Option<&str>>) -> (Self, Arc<Mutex<Vec<String>>>) {
            let sent = Arc::new(Mutex::new(Vec::new()));
            let hub = Self {
                script: script.into_iter().map(|m| m.map(String::from)).collect(),
                sent: sent.clone(),
                closed: Arc::new(AtomicBool::new(false)),
                on_recv: Box::new(|_| {}),
                reads: 0,
            };
            (hub, sent)
        }
    }

    impl Hub for FakeHub {
        fn send(&mut self, text: &str) -> Result<(), String> {
            self.sent.lock().unwrap().push(text.into());
            Ok(())
        }

        fn recv(&mut self, _: Duration) -> Result<Option<String>, String> {
            self.reads += 1;
            (self.on_recv)(self.reads);
            self.script
                .pop_front()
                .ok_or_else(|| "the hub closed the connection".to_string())
        }

        fn close(&mut self) {
            self.closed.store(true, Ordering::SeqCst);
        }
    }

    struct FakeLink {
        busy: Arc<AtomicBool>,
        model: Arc<Mutex<String>>,
        stop_after_reads: Option<usize>,
        tokens: Mutex<u32>,
    }

    impl FakeLink {
        fn new() -> Self {
            Self {
                busy: Arc::new(AtomicBool::new(false)),
                model: Arc::new(Mutex::new("model-a".into())),
                stop_after_reads: None,
                tokens: Mutex::new(0),
            }
        }
    }

    impl Link for FakeLink {
        fn busy(&self) -> bool {
            self.busy.load(Ordering::SeqCst)
        }

        fn model(&self) -> String {
            self.model.lock().unwrap().clone()
        }

        fn keep_going(&self) -> bool {
            self.stop_after_reads != Some(0)
        }

        fn fresh_token(&self) -> Result<String, String> {
            let mut n = self.tokens.lock().unwrap();
            *n += 1;
            Ok(format!("token-{n}"))
        }
    }

    fn who() -> Identity {
        Identity {
            relay_id: "r1".into(),
            name: "Shop".into(),
            build: "20261112".into(),
        }
    }

    fn quiet() -> Timings {
        Timings {
            tick: Duration::from_millis(1),
            ping: Duration::from_secs(3600),
            token: Duration::from_secs(3600),
            quiet: Duration::from_secs(3600),
        }
    }

    fn parsed(sent: &Arc<Mutex<Vec<String>>>) -> Vec<serde_json::Value> {
        sent.lock()
            .unwrap()
            .iter()
            .map(|m| serde_json::from_str(m).unwrap_or(serde_json::Value::String(m.clone())))
            .collect()
    }

    #[test]
    fn backs_off_from_one_second_to_a_minute_and_resets() {
        let mut backoff = Backoff::new();
        let waits: Vec<u64> = (0..9).map(|_| backoff.take().as_secs()).collect();
        assert_eq!(waits, [1, 2, 4, 8, 16, 32, 60, 60, 60]);
        backoff.reset();
        assert_eq!(backoff.take(), BACKOFF_FIRST);
    }

    #[test]
    fn says_hello_first_with_the_relay_details() {
        let (mut hub, sent) = FakeHub::new(vec![None]);
        let link = FakeLink::new();
        let result = serve(&host(), &mut hub, &link, &who(), &quiet());
        assert!(result.is_err());
        let messages = parsed(&sent);
        assert_eq!(messages[0]["type"], "hello");
        assert_eq!(messages[0]["relayId"], "r1");
        assert_eq!(messages[0]["name"], "Shop");
        assert_eq!(messages[0]["model"], "model-a");
        assert_eq!(messages[0]["build"], "20261112");
        assert_eq!(messages[0]["busy"], false);
        assert_eq!(messages.len(), 1);
    }

    #[test]
    fn a_bad_offer_is_rejected_with_its_session_id() {
        let offer = r#"{"type":"offer","sessionId":"s1","sdp":"not an sdp","iceServers":[]}"#;
        let (mut hub, sent) = FakeHub::new(vec![Some(offer), Some("pong"), None]);
        let result = serve(&host(), &mut hub, &FakeLink::new(), &who(), &quiet());
        assert!(result.is_err());
        let messages = parsed(&sent);
        assert_eq!(messages.len(), 2, "{messages:?}");
        assert_eq!(messages[1]["type"], "reject");
        assert_eq!(messages[1]["sessionId"], "s1");
        assert!(!messages[1]["message"].as_str().unwrap().is_empty());
    }

    #[test]
    fn sends_busy_only_when_it_changes() {
        let (mut hub, sent) = FakeHub::new(vec![None, None, None, None]);
        let link = FakeLink::new();
        let busy = link.busy.clone();
        hub.on_recv = Box::new(move |read| busy.store(read == 2 || read == 3, Ordering::SeqCst));
        let _ = serve(&host(), &mut hub, &link, &who(), &quiet());
        let busy_messages: Vec<_> = parsed(&sent)
            .into_iter()
            .filter(|m| m["type"] == "busy")
            .map(|m| m["busy"].clone())
            .collect();
        assert_eq!(busy_messages, [true, false]);
    }

    #[test]
    fn a_model_change_sends_hello_again() {
        let (mut hub, sent) = FakeHub::new(vec![None, None]);
        let link = FakeLink::new();
        let model = link.model.clone();
        hub.on_recv = Box::new(move |read| {
            if read == 2 {
                *model.lock().unwrap() = "model-b".into();
            }
        });
        let _ = serve(&host(), &mut hub, &link, &who(), &quiet());
        let models: Vec<_> = parsed(&sent)
            .into_iter()
            .filter(|m| m["type"] == "hello")
            .map(|m| m["model"].as_str().unwrap().to_owned())
            .collect();
        assert_eq!(models, ["model-a", "model-b"]);
    }

    #[test]
    fn pings_and_refreshes_the_token_on_their_timers() {
        let (mut hub, sent) = FakeHub::new(vec![None, None]);
        let timings = Timings {
            tick: Duration::from_millis(1),
            ping: Duration::ZERO,
            token: Duration::ZERO,
            quiet: Duration::from_secs(3600),
        };
        let _ = serve(&host(), &mut hub, &FakeLink::new(), &who(), &timings);
        let messages = parsed(&sent);
        let pings = messages.iter().filter(|m| *m == "ping").count();
        assert_eq!(pings, 2);
        let tokens: Vec<_> = messages
            .iter()
            .filter(|m| m["type"] == "token")
            .map(|m| m["token"].as_str().unwrap().to_owned())
            .collect();
        assert_eq!(tokens, ["token-1", "token-2"]);
    }

    #[test]
    fn a_silent_hub_ends_the_connection() {
        let (mut hub, _) = FakeHub::new(vec![None, None, None]);
        let timings = Timings {
            quiet: Duration::ZERO,
            ..quiet()
        };
        let result = serve(&host(), &mut hub, &FakeLink::new(), &who(), &timings);
        assert_eq!(result, Err("the hub went quiet".into()));
    }

    #[test]
    fn closes_the_socket_and_returns_ok_when_told_to_stop() {
        let (mut hub, _) = FakeHub::new(vec![]);
        let closed = hub.closed.clone();
        let mut link = FakeLink::new();
        link.stop_after_reads = Some(0);
        assert!(serve(&host(), &mut hub, &link, &who(), &quiet()).is_ok());
        assert!(closed.load(Ordering::SeqCst));
    }

    #[test]
    fn a_failed_token_refresh_ends_the_connection() {
        struct NoToken(FakeLink);
        impl Link for NoToken {
            fn busy(&self) -> bool {
                self.0.busy()
            }
            fn model(&self) -> String {
                self.0.model()
            }
            fn keep_going(&self) -> bool {
                true
            }
            fn fresh_token(&self) -> Result<String, String> {
                Err("the token service is down".into())
            }
        }
        let (mut hub, _) = FakeHub::new(vec![None, None]);
        let timings = Timings {
            token: Duration::ZERO,
            ..quiet()
        };
        let result = serve(
            &host(),
            &mut hub,
            &NoToken(FakeLink::new()),
            &who(),
            &timings,
        );
        assert_eq!(result.unwrap_err(), "the token service is down");
    }
}
