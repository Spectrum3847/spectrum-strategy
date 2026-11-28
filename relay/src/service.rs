use crate::answer::{
    REQUEST_TIMEOUT_MS, Request, Verdict, claim_fields, judge, looks_like_an_answer, summary_fields,
};
use crate::auth::{self, AuthError, SECURE_TOKEN, Session, StoredToken};
use crate::config::{self, Config, Dirs};
use crate::firebase_config::DATA_PROJECT_ID;
use crate::firestore::{self, Firestore};
use crate::llama::{self, Server};
use crate::timeutil::{iso, now_ms};
use serde::Serialize;
use std::fmt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

const POLL: Duration = Duration::from_secs(10);
const MAX_BACKOFF: Duration = Duration::from_secs(120);

const MODEL_IDLE: Duration = Duration::from_secs(5 * 60);

#[derive(Clone, Serialize)]
pub struct Event {
    pub text: String,
    #[serde(rename = "atMs")]
    pub at_ms: i64,
}

#[derive(Clone, Default, Serialize)]
pub struct State {
    pub signed_in_as: Option<String>,
    pub signed_in_uid: Option<String>,
    pub phase: String,
    pub llama_running: bool,
    pub last_answer: Option<Event>,
    pub last_error: Option<Event>,
    pub update: Option<Event>,
    pub chat_online: bool,
    pub chat_peers: usize,
    pub chat_error: Option<Event>,
}

#[derive(Clone)]
pub struct Ready {
    pub binary: PathBuf,
    pub model_file: PathBuf,
}

pub enum ModelError {

    Busy,
    Failed(String),
}

impl fmt::Display for ModelError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Busy => f.write_str("the model is busy"),
            Self::Failed(e) => f.write_str(e),
        }
    }
}

struct Generating<'a>(&'a AtomicBool);

impl<'a> Generating<'a> {
    fn start(flag: &'a AtomicBool) -> Self {
        flag.store(true, Ordering::SeqCst);
        Self(flag)
    }
}

impl Drop for Generating<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::SeqCst);
    }
}

pub struct Shared {
    pub dirs: Dirs,
    config: Mutex<Config>,
    state: Mutex<State>,
    nudged: Mutex<bool>,
    wake: Condvar,
    restart: AtomicBool,
    stopping: AtomicBool,
    update_requested: AtomicBool,
    session: Mutex<Session>,

    model: Mutex<Option<Server>>,
    ready: Mutex<Option<Ready>>,
    generating: AtomicBool,
}

impl Shared {
    pub fn new(dirs: Dirs) -> Arc<Self> {
        let mut config = config::load(&dirs.config_file());
        if config.relay_id.is_empty() {
            config.relay_id = config::new_relay_id();
            if let Err(e) = config::save(&dirs.config_file(), &config) {
                eprintln!("could not save the relay id: {e}");
            }
        }
        Arc::new(Self {
            dirs,
            config: Mutex::new(config),
            state: Mutex::new(State::default()),
            nudged: Mutex::new(false),
            wake: Condvar::new(),
            restart: AtomicBool::new(false),
            stopping: AtomicBool::new(false),
            update_requested: AtomicBool::new(false),
            session: Mutex::new(Session::new(SECURE_TOKEN)),
            model: Mutex::new(None),
            ready: Mutex::new(None),
            generating: AtomicBool::new(false),
        })
    }

    pub fn config(&self) -> Config {
        self.config.lock().unwrap().clone()
    }

    pub fn update_config(&self, change: impl FnOnce(&mut Config)) -> Result<(), String> {
        let mut config = self.config.lock().unwrap();
        change(&mut config);
        config::save(&self.dirs.config_file(), &config)?;
        drop(config);
        self.nudge();
        Ok(())
    }

    pub fn state(&self) -> State {
        self.state.lock().unwrap().clone()
    }

    pub fn update_state(&self, change: impl FnOnce(&mut State)) {
        change(&mut self.state.lock().unwrap());
    }

    pub fn phase(&self, text: impl Into<String>) {
        let text = text.into();
        self.update_state(|s| s.phase = text);
    }

    pub fn error(&self, text: impl Into<String>) {
        let text = text.into();
        eprintln!("error: {text}");
        self.update_state(|s| {
            s.last_error = Some(Event {
                text,
                at_ms: now_ms(),
            })
        });
    }

    pub fn nudge(&self) {
        *self.nudged.lock().unwrap() = true;
        self.wake.notify_all();
    }

    pub fn request_restart(&self) {
        self.restart.store(true, Ordering::SeqCst);
        self.nudge();
    }

    pub fn restart_requested(&self) -> bool {
        self.restart.load(Ordering::SeqCst)
    }

    pub fn request_stop(&self) {
        self.stopping.store(true, Ordering::SeqCst);
        self.request_restart();
    }

    pub fn stopping(&self) -> bool {
        self.stopping.load(Ordering::SeqCst)
    }

    pub fn id_token(&self, stored: &StoredToken) -> Result<String, AuthError> {
        self.session
            .lock()
            .unwrap()
            .id_token(stored, &self.dirs.token_file())
    }

    pub fn chat_error(&self, text: impl Into<String>) {
        let text = text.into();
        eprintln!("chat: {text}");
        self.update_state(|s| {
            s.chat_error = Some(Event {
                text,
                at_ms: now_ms(),
            })
        });
    }

    pub fn set_ready(&self, ready: Option<Ready>) {
        *self.ready.lock().unwrap() = ready;
    }

    pub fn ready(&self) -> Option<Ready> {
        self.ready.lock().unwrap().clone()
    }

    pub fn is_generating(&self) -> bool {
        self.generating.load(Ordering::SeqCst)
    }

    pub fn with_model<T>(
        &self,
        wait: bool,
        job: impl FnOnce(&Server) -> Result<T, String>,
    ) -> Result<T, ModelError> {
        let ready = self.ready().ok_or(ModelError::Busy)?;
        let mut slot = if wait {
            self.model.lock().unwrap()
        } else {
            self.model.try_lock().map_err(|_| ModelError::Busy)?
        };
        let _generating = Generating::start(&self.generating);
        if slot
            .as_mut()
            .is_some_and(|s| !s.alive() || s.model_file != ready.model_file)
        {
            *slot = None;
        }
        if slot.is_none() {
            self.phase("Starting llama-server");
            *slot = Some(
                Server::start(
                    &ready.binary,
                    &ready.model_file,
                    &self.dirs.llama_log(),
                    llama::CONTEXT_TOKENS,
                )
                .map_err(ModelError::Failed)?,
            );
        }
        self.update_state(|s| s.llama_running = true);
        let server = slot.as_mut().unwrap();
        let outcome = job(server);
        server.last_used = Instant::now();
        outcome.map_err(ModelError::Failed)
    }

    pub fn stop_model(&self) {
        if let Ok(mut slot) = self.model.try_lock() {
            *slot = None;
            self.update_state(|s| s.llama_running = false);
        }
    }

    fn stop_model_if_idle(&self, idle: Duration) {
        if let Ok(mut slot) = self.model.try_lock()
            && slot.as_ref().is_some_and(|s| s.last_used.elapsed() > idle)
        {
            *slot = None;
            self.update_state(|s| s.llama_running = false);
        }
    }

    pub fn request_update_check(&self) {
        self.update_requested.store(true, Ordering::SeqCst);
    }

    pub fn update_requested(&self) -> bool {
        self.update_requested.load(Ordering::SeqCst)
    }

    pub fn take_update_request(&self) -> bool {
        self.update_requested.swap(false, Ordering::SeqCst)
    }

    fn sleep(&self, duration: Duration) {
        let guard = self.nudged.lock().unwrap();
        let (mut guard, _) = self
            .wake
            .wait_timeout_while(guard, duration, |nudged| !*nudged)
            .unwrap();
        *guard = false;
    }
}

pub enum Outcome {

    Idle,
    Answered(String),

    Failed(String),
}

pub fn answer_next(
    fs: &Firestore,
    token: &str,
    uid: &str,
    now: i64,
    model_name: &str,
    ask: &mut dyn FnMut(&Request) -> Result<String, String>,
) -> Result<Outcome, String> {
    let cutoff = iso(now - REQUEST_TIMEOUT_MS);
    for (id, fields) in fs.open_requests(token, &cutoff)? {
        let request = match Request::parse(&id, &fields) {
            Ok(request) => request,
            Err(e) => {
                eprintln!("skipping a request: {e}");
                continue;
            }
        };
        if judge(&request, uid, now) != Verdict::Take {
            continue;
        }
        if !fs.claim(token, &id, &claim_fields(uid, now))? {
            continue;
        }
        let answer = match ask(&request) {
            Ok(text) => text,
            Err(e) => return Ok(Outcome::Failed(format!("{}: {e}", request.cache_key))),
        };
        if !looks_like_an_answer(&answer, request.minimum_chars) {
            return Ok(Outcome::Failed(format!(
                "{}: the model did not give an answer",
                request.cache_key
            )));
        }
        let summary = summary_fields(
            &request,
            &answer,
            model_name,
            uid,
            crate::timeutil::now_ms(),
        );
        fs.write_summary(token, &id, &summary)?;
        if let Err(e) = fs.delete_request(token, &id) {
            eprintln!("answered, but could not delete the request: {e}");
        }
        return Ok(Outcome::Answered(request.cache_key));
    }
    Ok(Outcome::Idle)
}

struct Backoff(Duration);

impl Backoff {
    fn reset(&mut self) {
        self.0 = POLL;
    }
    fn next(&mut self) -> Duration {
        let wait = self.0;
        self.0 = (self.0 * 2).min(MAX_BACKOFF);
        wait
    }
}

pub fn run(shared: &Arc<Shared>) {
    let firestore = Firestore::new(firestore::PRODUCTION, DATA_PROJECT_ID);
    let mut backoff = Backoff(POLL);
    let token_path = shared.dirs.token_file();

    while !shared.restart_requested() {
        let config = shared.config();
        if !config.enabled {
            shared.set_ready(None);
            shared.stop_model();
            shared.phase("Off");
            shared.sleep(Duration::from_secs(5));
            continue;
        }
        let Some(stored) = auth::load_token(&token_path) else {
            shared.update_state(|s| {
                s.signed_in_as = None;
                s.signed_in_uid = None;
            });
            shared.phase("Waiting for sign-in");
            shared.sleep(Duration::from_secs(5));
            continue;
        };
        shared.update_state(|s| {
            s.signed_in_as = Some(stored.email.clone());
            s.signed_in_uid = Some(stored.uid.clone());
        });

        let progress = |text: String| shared.phase(text);
        let setup = llama::ensure_runtime(&shared.dirs.llama_dir(), &progress).and_then(|binary| {
            llama::ensure_model(&shared.dirs.models_dir(), &config.model, &progress)
                .map(|model| (binary, model))
        });
        let (binary, model_file) = match setup {
            Ok(ready) => ready,
            Err(e) => {
                shared.error(e);
                shared.phase("Setup failed, will retry");
                shared.sleep(backoff.next());
                continue;
            }
        };

        shared.set_ready(Some(Ready { binary, model_file }));

        let token = match shared.id_token(&stored) {
            Ok(token) => token,
            Err(AuthError::Refused(e)) => {
                auth::clear_token(&token_path);
                shared.error(format!("{e}. Sign in again."));
                continue;
            }
            Err(AuthError::Transient(e)) => {
                shared.error(e);
                shared.sleep(backoff.next());
                continue;
            }
        };

        shared.phase("Watching for requests");
        let mut ask = |request: &Request| {
            shared.phase("Answering a request");
            shared
                .with_model(true, |server| {
                    llama::chat(
                        &server.url,
                        &config.model.name,
                        request.system.as_deref(),
                        &request.prompt,
                    )
                })
                .map_err(|e| e.to_string())
        };
        let outcome = answer_next(
            &firestore,
            &token,
            &stored.uid,
            now_ms(),
            &config.model.name,
            &mut ask,
        );
        match outcome {
            Ok(Outcome::Answered(key)) => {
                backoff.reset();
                shared.update_state(|s| {
                    s.last_answer = Some(Event {
                        text: key,
                        at_ms: now_ms(),
                    });
                });
            }
            Ok(Outcome::Failed(e)) => shared.error(e),
            Ok(Outcome::Idle) => {
                backoff.reset();
                shared.stop_model_if_idle(MODEL_IDLE);
                shared.sleep(POLL);
            }
            Err(e) => {
                shared.error(e);
                shared.sleep(backoff.next());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_doubles_to_a_ceiling_and_resets() {
        let mut backoff = Backoff(POLL);
        assert_eq!(backoff.next(), Duration::from_secs(10));
        assert_eq!(backoff.next(), Duration::from_secs(20));
        for _ in 0..10 {
            backoff.next();
        }
        assert_eq!(backoff.next(), MAX_BACKOFF);
        backoff.reset();
        assert_eq!(backoff.next(), POLL);
    }

    #[test]
    fn a_nudge_wakes_the_sleeper() {
        let dir = std::env::temp_dir().join(format!("relay-nudge-{}", std::process::id()));
        let shared = Shared::new(Dirs {
            config: dir.join("c"),
            data: dir.join("d"),
        });
        shared.nudge();
        let started = Instant::now();
        shared.sleep(Duration::from_secs(30));
        assert!(started.elapsed() < Duration::from_secs(5));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_new_relay_keeps_the_same_id_across_restarts() {
        let dir = std::env::temp_dir().join(format!("relay-id-{}", std::process::id()));
        let dirs = || Dirs {
            config: dir.join("c"),
            data: dir.join("d"),
        };
        let first = Shared::new(dirs()).config().relay_id;
        assert_eq!(first.len(), 32);
        assert_eq!(Shared::new(dirs()).config().relay_id, first);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_model_is_busy_until_it_is_ready() {
        let dir = std::env::temp_dir().join(format!("relay-ready-{}", std::process::id()));
        let shared = Shared::new(Dirs {
            config: dir.join("c"),
            data: dir.join("d"),
        });
        let result = shared.with_model(false, |_| Ok(()));
        assert!(matches!(result, Err(ModelError::Busy)));
        assert!(!shared.is_generating());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
