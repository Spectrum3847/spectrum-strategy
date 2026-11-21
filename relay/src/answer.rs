use crate::firestore::{integer, string, timestamp};
use crate::timeutil::iso;
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};

pub const CLAIM_TIMEOUT_MS: i64 = 3 * 60_000;

pub const REQUEST_TIMEOUT_MS: i64 = 10 * 60_000;

const MAX_TEXT: usize = 8000;
const MAX_MODEL: usize = 128;

const NON_ANSWER_OPENINGS: [&str; 10] = [
    "user safety:",
    "safety:",
    "i cannot",
    "i can't",
    "i am unable",
    "i'm unable",
    "i am sorry",
    "i'm sorry",
    "as an ai",
    "as a language model",
];

fn utf16_len(text: &str) -> usize {
    text.encode_utf16().count()
}

pub fn looks_like_an_answer(text: &str, minimum_chars: Option<usize>) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() || minimum_chars.is_some_and(|min| utf16_len(trimmed) < min) {
        return false;
    }
    let opening = trimmed.to_lowercase();
    !NON_ANSWER_OPENINGS.iter().any(|p| opening.starts_with(p))
}

pub fn cache_doc_id(cache_key: &str) -> String {
    Sha256::digest(cache_key.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[derive(Clone, Debug, PartialEq)]
pub struct Request {
    pub id: String,
    pub cache_key: String,
    pub system: Option<String>,
    pub prompt: String,
    pub minimum_chars: Option<usize>,
    pub coverage: Option<i64>,
    pub requested_by: String,
    pub requested_at_ms: i64,
    pub claimed_by: Option<String>,
    pub claimed_at_ms: Option<i64>,
}

fn text<'a>(fields: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    fields.get(key)?.as_str().filter(|s| !s.is_empty())
}

impl Request {

    pub fn parse(id: &str, fields: &Value) -> Result<Self, String> {
        let fields = fields.as_object().ok_or("document has no fields")?;
        let need = |key: &str| text(fields, key).ok_or(format!("{id}: missing {key}"));
        let requested_at = need("requestedAt")?;
        Ok(Self {
            id: id.into(),
            cache_key: need("cacheKey")?.into(),
            system: text(fields, "system").map(Into::into),
            prompt: need("prompt")?.into(),
            minimum_chars: fields
                .get("minimumChars")
                .and_then(Value::as_u64)
                .map(|n| n as usize),
            coverage: fields.get("coverage").and_then(Value::as_i64),
            requested_by: need("requestedBy")?.into(),
            requested_at_ms: crate::timeutil::parse_iso(requested_at)
                .ok_or(format!("{id}: bad requestedAt"))?,
            claimed_by: text(fields, "claimedBy").map(Into::into),
            claimed_at_ms: text(fields, "claimedAt").and_then(crate::timeutil::parse_iso),
        })
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum Verdict {
    Take,

    Own,
    Stale,

    Claimed,

    BadId,
}

pub fn judge(request: &Request, uid: &str, now_ms: i64) -> Verdict {
    if cache_doc_id(&request.cache_key) != request.id {
        return Verdict::BadId;
    }
    if request.requested_by == uid {
        return Verdict::Own;
    }
    if now_ms - request.requested_at_ms > REQUEST_TIMEOUT_MS {
        return Verdict::Stale;
    }
    match (&request.claimed_by, request.claimed_at_ms) {
        (Some(_), Some(at)) if now_ms - at < CLAIM_TIMEOUT_MS => Verdict::Claimed,
        _ => Verdict::Take,
    }
}

pub fn claim_fields(uid: &str, now_ms: i64) -> Value {
    json!({ "claimedBy": string(uid), "claimedAt": string(&iso(now_ms)) })
}

pub fn truncate_utf16(text: &str, max: usize) -> String {
    let mut units = 0;
    text.chars()
        .take_while(|c| {
            units += c.len_utf16();
            units <= max
        })
        .collect()
}

pub fn summary_fields(
    request: &Request,
    answer: &str,
    model: &str,
    uid: &str,
    now_ms: i64,
) -> Value {
    let now = iso(now_ms);
    let mut fields = json!({
        "cacheKey": string(&request.cache_key),
        "text": string(&truncate_utf16(answer.trim(), MAX_TEXT)),
        "model": string(&truncate_utf16(model, MAX_MODEL)),
        "source": string("local"),
        "generatedAt": string(&now),
        "authorUid": string(uid),
        "updatedAt": string(&now),
        "updatedAtTs": timestamp(&now),
    });
    if let Some(coverage) = request.coverage {
        fields["coverage"] = integer(coverage);
    }
    fields
}

pub fn answer_from(body: &Value) -> Option<String> {
    let message = body.pointer("/choices/0/message")?;
    let pick = |key: &str| {
        message
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
    };
    pick("content")
        .or_else(|| pick("reasoning_content"))
        .map(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::firestore::decode_fields;

    const NOW: i64 = 1_800_000_000_000;

    fn request() -> Request {
        let key = "comment-digest:2026txhou:3847";
        Request {
            id: cache_doc_id(key),
            cache_key: key.into(),
            system: Some("system".into()),
            prompt: "prompt".into(),
            minimum_chars: Some(80),
            coverage: Some(7),
            requested_by: "poster".into(),
            requested_at_ms: NOW - 5_000,
            claimed_by: None,
            claimed_at_ms: None,
        }
    }

    #[test]
    fn answer_check_matches_the_app() {
        let long = "x".repeat(80);
        assert!(looks_like_an_answer(&long, Some(80)));
        assert!(!looks_like_an_answer(&"x".repeat(79), Some(80)));
        assert!(!looks_like_an_answer("   ", None));
        assert!(looks_like_an_answer("short", None));
        for opening in [
            "User Safety: safe",
            "  I cannot help with that, sorry.",
            "I'm sorry, but",
            "As an AI model",
            "As a language model",
        ] {
            assert!(!looks_like_an_answer(opening, None), "{opening}");
        }
        assert!(looks_like_an_answer(
            "Scouters agree the robot is fast",
            None
        ));
    }

    #[test]
    fn answer_length_counts_utf16_units() {

        let text = "\u{1F600}".repeat(40);
        assert!(looks_like_an_answer(&text, Some(80)));
    }

    #[test]
    fn doc_id_is_the_sha256_of_the_key() {
        assert_eq!(
            cache_doc_id("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn parses_what_the_pwa_posts() {
        let key = "comment-digest:2026txhou:3847";
        let rest = json!({
            "cacheKey": { "stringValue": key },
            "system": { "stringValue": "sys" },
            "prompt": { "stringValue": "p" },
            "minimumChars": { "integerValue": "80" },
            "coverage": { "integerValue": "7" },
            "requestedBy": { "stringValue": "u1" },
            "requestedAt": { "stringValue": "2026-11-10T12:00:00.000Z" },
        });
        let parsed = Request::parse(&cache_doc_id(key), &decode_fields(&rest)).unwrap();
        assert_eq!(parsed.minimum_chars, Some(80));
        assert_eq!(parsed.coverage, Some(7));
        assert_eq!(parsed.system.as_deref(), Some("sys"));
        assert_eq!(parsed.claimed_by, None);
    }

    #[test]
    fn optional_fields_may_be_absent_and_required_ones_may_not() {
        let rest = json!({
            "cacheKey": { "stringValue": "k" },
            "prompt": { "stringValue": "p" },
            "requestedBy": { "stringValue": "u1" },
            "requestedAt": { "stringValue": "2026-11-10T12:00:00Z" },
        });
        let plain = decode_fields(&rest);
        let parsed = Request::parse("id", &plain).unwrap();
        assert_eq!(parsed.system, None);
        assert_eq!(parsed.minimum_chars, None);

        let mut missing = rest.clone();
        missing.as_object_mut().unwrap().remove("prompt");
        assert!(Request::parse("id", &decode_fields(&missing)).is_err());
        assert!(Request::parse("id", &json!(null)).is_err());
    }

    #[test]
    fn takes_a_fresh_unclaimed_request() {
        assert_eq!(judge(&request(), "relay", NOW), Verdict::Take);
    }

    #[test]
    fn skips_its_own_stale_and_badly_named_requests() {
        assert_eq!(judge(&request(), "poster", NOW), Verdict::Own);
        let mut old = request();
        old.requested_at_ms = NOW - REQUEST_TIMEOUT_MS - 1;
        assert_eq!(judge(&old, "relay", NOW), Verdict::Stale);
        let mut renamed = request();
        renamed.id = "other".into();
        assert_eq!(judge(&renamed, "relay", NOW), Verdict::BadId);
    }

    #[test]
    fn respects_a_recent_claim_and_retakes_an_old_one() {
        let mut claimed = request();
        claimed.claimed_by = Some("someone".into());
        claimed.claimed_at_ms = Some(NOW - 60_000);
        assert_eq!(judge(&claimed, "relay", NOW), Verdict::Claimed);
        claimed.claimed_at_ms = Some(NOW - CLAIM_TIMEOUT_MS);
        assert_eq!(judge(&claimed, "relay", NOW), Verdict::Take);
    }

    #[test]
    fn summary_uses_only_keys_the_rules_allow() {
        let allowed = [
            "cacheKey",
            "text",
            "model",
            "source",
            "coverage",
            "generatedAt",
            "authorUid",
            "updatedAt",
            "updatedAtTs",
        ];
        let fields = summary_fields(&request(), " An answer. ", "m", "relay", NOW);
        let object = fields.as_object().unwrap();
        assert!(object.keys().all(|k| allowed.contains(&k.as_str())));
        assert_eq!(object.len(), allowed.len());
        assert_eq!(fields["source"]["stringValue"], "local");
        assert_eq!(fields["text"]["stringValue"], "An answer.");
        assert_eq!(fields["coverage"]["integerValue"], "7");
        assert!(fields["updatedAtTs"]["timestampValue"].is_string());
        assert_eq!(fields["authorUid"]["stringValue"], "relay");
    }

    #[test]
    fn summary_omits_coverage_when_the_request_has_none() {
        let mut req = request();
        req.coverage = None;
        let fields = summary_fields(&req, "a", "m", "relay", NOW);
        assert!(fields.get("coverage").is_none());
    }

    #[test]
    fn summary_stays_inside_the_rules_limits() {
        let fields = summary_fields(
            &request(),
            &"é".repeat(9000),
            &"m".repeat(300),
            "relay",
            NOW,
        );
        assert_eq!(
            fields["text"]["stringValue"]
                .as_str()
                .unwrap()
                .chars()
                .count(),
            8000
        );
        assert_eq!(fields["model"]["stringValue"].as_str().unwrap().len(), 128);
    }

    #[test]
    fn text_limit_counts_utf16_units() {

        let fields = summary_fields(&request(), &"\u{1F600}".repeat(5000), "m", "relay", NOW);
        let text = fields["text"]["stringValue"].as_str().unwrap();
        assert_eq!(text.encode_utf16().count(), 8000);
        assert_eq!(text.chars().count(), 4000);
    }

    #[test]
    fn claim_writes_only_the_claim_fields() {
        let fields = claim_fields("relay", NOW);
        assert_eq!(fields.as_object().unwrap().len(), 2);
        assert_eq!(fields["claimedBy"]["stringValue"], "relay");
    }

    #[test]
    fn reads_the_answer_from_a_chat_completion() {
        let body = json!({"choices":[{"message":{"content":"  hello "}}]});
        assert_eq!(answer_from(&body).as_deref(), Some("hello"));
        let thinking = json!({"choices":[{"message":{"content":"","reasoning_content":"deep"}}]});
        assert_eq!(answer_from(&thinking).as_deref(), Some("deep"));
        assert_eq!(answer_from(&json!({"choices":[]})), None);
        assert_eq!(
            answer_from(&json!({"choices":[{"message":{"content":" "}}]})),
            None
        );
    }
}
