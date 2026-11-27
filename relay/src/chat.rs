use crate::answer::looks_like_an_answer;
use serde_json::{Value, json};

pub const CHANNEL_LABEL: &str = "chat";
pub const MAX_SYSTEM: usize = 8000;
pub const MAX_PROMPT: usize = 200_000;
pub const MAX_TOKENS: u32 = 2048;
pub const DEFAULT_TOKENS: u32 = 1024;
const MAX_ID: usize = 128;

const OPENING_CHARS: usize = 24;

#[derive(Debug, PartialEq)]
pub struct Ask {
    pub id: String,
    pub system: Option<String>,
    pub prompt: String,
    pub max_tokens: u32,
}

#[derive(Debug, PartialEq)]
pub enum Incoming {
    Ask(Ask),
    Cancel(String),

    Rejected {
        id: Option<String>,
        reason: String,
    },
}

fn reject(id: Option<String>, reason: &str) -> Incoming {
    Incoming::Rejected {
        id,
        reason: reason.into(),
    }
}

pub fn parse_incoming(text: &str) -> Incoming {
    let Ok(value) = serde_json::from_str::<Value>(text) else {
        return reject(None, "the message is not JSON");
    };
    let id = value
        .get("id")
        .and_then(Value::as_str)
        .filter(|id| !id.is_empty() && id.chars().count() <= MAX_ID)
        .map(str::to_owned);
    match (value.get("type").and_then(Value::as_str), id) {
        (Some("cancel"), Some(id)) => Incoming::Cancel(id),
        (Some("cancel"), None) => reject(None, "a cancel needs an id"),
        (Some("ask"), Some(id)) => parse_ask(&value, id),
        (Some("ask"), None) => reject(None, "an ask needs an id"),
        (_, id) => reject(id, "unknown message type"),
    }
}

fn parse_ask(value: &Value, id: String) -> Incoming {
    let prompt = value.get("prompt").and_then(Value::as_str).unwrap_or("");
    if prompt.trim().is_empty() {
        return reject(Some(id), "the prompt is empty");
    }
    if prompt.chars().count() > MAX_PROMPT {
        return reject(Some(id), "the prompt is too long");
    }
    let system = value
        .get("system")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty());
    if system.is_some_and(|s| s.chars().count() > MAX_SYSTEM) {
        return reject(Some(id), "the system text is too long");
    }
    let max_tokens = match value.get("maxTokens") {
        None | Some(Value::Null) => DEFAULT_TOKENS,
        Some(n) => match n.as_u64() {
            Some(n) if (1..=u64::from(MAX_TOKENS)).contains(&n) => n as u32,
            _ => return reject(Some(id), "maxTokens is out of range"),
        },
    };
    Incoming::Ask(Ask {
        id,
        system: system.map(str::to_owned),
        prompt: prompt.to_owned(),
        max_tokens,
    })
}

pub fn chunk(id: &str, text: &str) -> String {
    json!({ "type": "chunk", "id": id, "text": text }).to_string()
}

pub fn done(id: &str, model: &str) -> String {
    json!({ "type": "done", "id": id, "model": model }).to_string()
}

pub fn error(id: &str, message: &str) -> String {
    json!({ "type": "error", "id": id, "message": message }).to_string()
}

pub enum Gate {

    Hold,
    Send(String),

    Refused,
}

#[derive(Default)]
pub struct OpeningGate {
    held: String,
    passed: bool,
}

impl OpeningGate {
    pub fn push(&mut self, text: &str) -> Gate {
        if self.passed {
            return Gate::Send(text.to_owned());
        }
        self.held.push_str(text);
        if self.held.trim().chars().count() < OPENING_CHARS {
            return Gate::Hold;
        }
        self.judge()
    }

    pub fn finish(&mut self) -> Gate {
        if self.passed {
            return Gate::Send(String::new());
        }
        self.judge()
    }

    fn judge(&mut self) -> Gate {
        if !looks_like_an_answer(&self.held, None) {
            return Gate::Refused;
        }
        self.passed = true;
        Gate::Send(std::mem::take(&mut self.held))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ask(extra: &str) -> String {
        format!(r#"{{"type":"ask","id":"a1","prompt":"who?"{extra}}}"#)
    }

    #[test]
    fn parses_an_ask_with_defaults() {
        let parsed = parse_incoming(&ask(""));
        assert_eq!(
            parsed,
            Incoming::Ask(Ask {
                id: "a1".into(),
                system: None,
                prompt: "who?".into(),
                max_tokens: DEFAULT_TOKENS,
            })
        );
    }

    #[test]
    fn parses_system_and_token_limit() {
        let Incoming::Ask(ask) = parse_incoming(&ask(r#","system":"be brief","maxTokens":2048"#))
        else {
            panic!("not an ask");
        };
        assert_eq!(ask.system.as_deref(), Some("be brief"));
        assert_eq!(ask.max_tokens, 2048);
    }

    #[test]
    fn an_empty_system_is_no_system() {
        let Incoming::Ask(ask) = parse_incoming(&ask(r#","system":"""#)) else {
            panic!("not an ask");
        };
        assert_eq!(ask.system, None);
    }

    #[test]
    fn refuses_an_ask_over_the_limits() {
        let long_prompt = format!(
            r#"{{"type":"ask","id":"a1","prompt":"{}"}}"#,
            "x".repeat(MAX_PROMPT + 1)
        );
        let at_limit = format!(
            r#"{{"type":"ask","id":"a1","prompt":"{}"}}"#,
            "x".repeat(MAX_PROMPT)
        );
        assert!(matches!(
            parse_incoming(&long_prompt),
            Incoming::Rejected { id: Some(_), .. }
        ));
        assert!(matches!(parse_incoming(&at_limit), Incoming::Ask(_)));
        let long_system = ask(&format!(r#","system":"{}""#, "s".repeat(MAX_SYSTEM + 1)));
        assert!(matches!(
            parse_incoming(&long_system),
            Incoming::Rejected { .. }
        ));
        for tokens in ["2049", "0", "-1", "1.5", r#""many""#] {
            let parsed = parse_incoming(&ask(&format!(r#","maxTokens":{tokens}"#)));
            assert!(matches!(parsed, Incoming::Rejected { .. }), "{tokens}");
        }
    }

    #[test]
    fn the_limits_count_characters_not_bytes() {
        let prompt = "\u{e9}".repeat(MAX_PROMPT);
        let text = format!(r#"{{"type":"ask","id":"a1","prompt":"{prompt}"}}"#);
        assert!(matches!(parse_incoming(&text), Incoming::Ask(_)));
    }

    #[test]
    fn rejects_what_it_cannot_serve_and_names_the_ask_when_it_can() {
        let missing_prompt = r#"{"type":"ask","id":"a1"}"#;
        assert_eq!(
            parse_incoming(missing_prompt),
            Incoming::Rejected {
                id: Some("a1".into()),
                reason: "the prompt is empty".into()
            }
        );
        let no_id = parse_incoming(r#"{"type":"ask","prompt":"who?"}"#);
        assert!(matches!(no_id, Incoming::Rejected { id: None, .. }));
        assert!(matches!(
            parse_incoming("not json"),
            Incoming::Rejected { id: None, .. }
        ));
        assert!(matches!(
            parse_incoming(r#"{"type":"chunk","id":"a1","text":"x"}"#),
            Incoming::Rejected { id: Some(_), .. }
        ));
        let long_id = format!(r#"{{"type":"cancel","id":"{}"}}"#, "i".repeat(129));
        assert!(matches!(
            parse_incoming(&long_id),
            Incoming::Rejected { .. }
        ));
    }

    #[test]
    fn parses_a_cancel() {
        assert_eq!(
            parse_incoming(r#"{"type":"cancel","id":"a1"}"#),
            Incoming::Cancel("a1".into())
        );
        assert!(matches!(
            parse_incoming(r#"{"type":"cancel"}"#),
            Incoming::Rejected { id: None, .. }
        ));
    }

    #[test]
    fn outgoing_messages_have_the_protocol_shape() {
        let chunk: Value = serde_json::from_str(&chunk("a1", "Hel\"lo")).unwrap();
        assert_eq!(
            chunk,
            json!({ "type": "chunk", "id": "a1", "text": "Hel\"lo" })
        );
        let done: Value = serde_json::from_str(&done("a1", "m")).unwrap();
        assert_eq!(done, json!({ "type": "done", "id": "a1", "model": "m" }));
        let error: Value = serde_json::from_str(&error("a1", "busy")).unwrap();
        assert_eq!(
            error,
            json!({ "type": "error", "id": "a1", "message": "busy" })
        );
    }

    fn sent(gate: Gate) -> Option<String> {
        match gate {
            Gate::Send(text) => Some(text),
            _ => None,
        }
    }

    #[test]
    fn the_gate_holds_the_opening_then_releases_it_whole() {
        let mut gate = OpeningGate::default();
        assert!(matches!(gate.push("Team 3847 "), Gate::Hold));
        assert!(matches!(gate.push("is a strong "), Gate::Hold));
        let released = sent(gate.push("pick for second"));
        assert_eq!(
            released.as_deref(),
            Some("Team 3847 is a strong pick for second")
        );
        assert_eq!(sent(gate.push(" seat.")).as_deref(), Some(" seat."));
        assert_eq!(sent(gate.finish()).as_deref(), Some(""));
    }

    #[test]
    fn the_gate_refuses_a_refusal_before_anything_is_sent() {
        let mut gate = OpeningGate::default();
        assert!(matches!(gate.push("I cannot help "), Gate::Hold));
        assert!(matches!(gate.push("with that request."), Gate::Refused));
        let mut verdict = OpeningGate::default();
        assert!(matches!(verdict.push("User Safety: safe"), Gate::Hold));
        assert!(matches!(verdict.finish(), Gate::Refused));
    }

    #[test]
    fn the_gate_judges_a_short_reply_when_the_stream_ends() {
        let mut gate = OpeningGate::default();
        assert!(matches!(gate.push("Team 254."), Gate::Hold));
        assert_eq!(sent(gate.finish()).as_deref(), Some("Team 254."));
        let mut empty = OpeningGate::default();
        assert!(matches!(empty.finish(), Gate::Refused));
        let mut blank = OpeningGate::default();
        assert!(matches!(blank.push("   "), Gate::Hold));
        assert!(matches!(blank.finish(), Gate::Refused));
    }
}
