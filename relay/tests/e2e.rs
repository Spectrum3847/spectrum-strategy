use serde_json::{Value, json};
use spectrum_relay::answer::cache_doc_id;
use spectrum_relay::firestore::{Firestore, integer, string};
use spectrum_relay::llama;
use spectrum_relay::service::{Outcome, answer_next};
use spectrum_relay::timeutil::{iso, now_ms};
use std::path::Path;

const PROJECT: &str = "demo-relay";

fn base64url(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let n = chunk
            .iter()
            .enumerate()
            .fold(0u32, |n, (i, b)| n | u32::from(*b) << (16 - 8 * i));
        for i in 0..=chunk.len() {
            out.push(TABLE[(n >> (18 - 6 * i) & 63) as usize] as char);
        }
    }
    out
}

fn token(uid: &str) -> String {
    let header = base64url(br#"{"alg":"none","typ":"JWT"}"#);
    let claims = json!({ "user_id": uid, "sub": uid, "aud": PROJECT, "iss": "x" });
    format!("{header}.{}.", base64url(claims.to_string().as_bytes()))
}

struct Db {
    agent: ureq::Agent,
    documents: String,
}

impl Db {
    fn new(base: &str) -> Self {
        Self {
            agent: ureq::Agent::config_builder()
                .http_status_as_error(false)
                .build()
                .into(),
            documents: format!("{base}/v1/projects/{PROJECT}/databases/(default)/documents"),
        }
    }

    fn put(&self, path: &str, bearer: &str, fields: Value) -> u16 {
        let url = format!("{}/{path}", self.documents);
        let response = self
            .agent
            .patch(&url)
            .header("Authorization", format!("Bearer {bearer}"))
            .send_json(json!({ "fields": fields }))
            .unwrap();
        response.status().as_u16()
    }

    fn get(&self, path: &str, bearer: &str) -> (u16, Value) {
        let url = format!("{}/{path}", self.documents);
        let mut response = self
            .agent
            .get(&url)
            .header("Authorization", format!("Bearer {bearer}"))
            .call()
            .unwrap();
        let status = response.status().as_u16();
        (
            status,
            response.body_mut().read_json().unwrap_or(Value::Null),
        )
    }
}

fn member(db: &Db, uid: &str) {
    let roles = json!({ "arrayValue": { "values": [{ "stringValue": "scouter" }] } });
    assert_eq!(
        db.put(
            &format!("userProfiles/{uid}"),
            "owner",
            json!({ "roles": roles })
        ),
        200
    );
}

fn post_request(db: &Db, key: &str, by: &str, prompt: &str) -> String {
    let id = cache_doc_id(key);
    let fields = json!({
        "cacheKey": string(key),
        "system": string("You summarise FRC scouting comments for a strategy lead. Be concrete and short."),
        "prompt": string(prompt),
        "minimumChars": integer(80),
        "coverage": integer(5),
        "requestedBy": string(by),
        "requestedAt": string(&iso(now_ms())),
    });
    assert_eq!(
        db.put(&format!("assistantRequests/{id}"), &token(by), fields),
        200,
        "post request"
    );
    id
}

const COMMENTS: &str = "Below are 5 comments written by scouters about team 3847 at one event.\n\n\
Write, in at most six lines:\n- What the scouters keep saying about this robot.\n\
- Where the scouters disagree with each other.\n- Anything a drive team would want warning about.\n\n\
Do not repeat the comments back. Do not add a preamble.\n\nComments:\n<<<UNTRUSTED_TEXT>>>\n\
- match Q5, by Ana: fast swerve, scores 4 coral per cycle\n\
- match Q9, by Ben: climbed late, missed the deep climb twice\n\
- match Q12, by Cy: drivers play heavy defence on the left side\n\
- match Q14, by Dee: lost comms for half the match, brownout\n\
- match Q20, by Eli: fast intake, but dropped algae often\n<<<END_UNTRUSTED_TEXT>>>\n";

#[test]
#[ignore]
fn answers_a_request_through_the_real_rules() {
    let var = |name: &str| std::env::var(name).unwrap_or_else(|_| panic!("set {name}"));
    let emulator = var("RELAY_E2E_FIRESTORE");
    let log = std::env::temp_dir().join("relay-e2e-llama.log");
    let server = llama::Server::start(
        Path::new(&var("RELAY_E2E_LLAMA_BIN")),
        Path::new(&var("RELAY_E2E_MODEL")),
        &log,
        8192,
    )
    .unwrap();
    let db = Db::new(&emulator);
    let fs = Firestore::new(&emulator, PROJECT);
    member(&db, "relay-uid");
    member(&db, "poster-uid");

    let probe = summary_fields_for_probe();
    assert_eq!(
        db.put("assistantSummaries/probe", &token("stranger-uid"), probe),
        403
    );

    let run = now_ms();
    let own = post_request(
        &db,
        &format!("comment-digest:own:{run}"),
        "relay-uid",
        COMMENTS,
    );
    let id = post_request(
        &db,
        &format!("comment-digest:{run}:3847"),
        "poster-uid",
        COMMENTS,
    );

    let relay_token = token("relay-uid");
    let asked = std::cell::Cell::new(0);
    let mut ask = |request: &spectrum_relay::answer::Request| {
        asked.set(asked.get() + 1);
        llama::chat(
            &server.url,
            "e2e",
            request.system.as_deref(),
            &request.prompt,
        )
    };
    let outcome = answer_next(
        &fs,
        &relay_token,
        "relay-uid",
        now_ms(),
        "e2e model",
        &mut ask,
    )
    .unwrap();
    match outcome {
        Outcome::Answered(key) => assert_eq!(key, format!("comment-digest:{run}:3847")),
        Outcome::Failed(e) => panic!("failed: {e}"),
        Outcome::Idle => panic!("nothing answered"),
    }
    assert_eq!(asked.get(), 1, "the relay's own request is not answered");

    let (status, summary) = db.get(&format!("assistantSummaries/{id}"), &token("poster-uid"));
    assert_eq!(status, 200);
    let text = summary["fields"]["text"]["stringValue"].as_str().unwrap();
    println!("summary ({} chars):\n{text}", text.len());
    assert!(text.len() >= 80);
    assert_eq!(summary["fields"]["source"]["stringValue"], "local");
    assert_eq!(summary["fields"]["coverage"]["integerValue"], "5");
    assert_eq!(summary["fields"]["authorUid"]["stringValue"], "relay-uid");

    assert_eq!(
        db.get(&format!("assistantRequests/{id}"), &token("poster-uid"))
            .0,
        404
    );
    assert_eq!(
        db.get(&format!("assistantRequests/{own}"), &token("poster-uid"))
            .0,
        200
    );

    let again = answer_next(
        &fs,
        &relay_token,
        "relay-uid",
        now_ms(),
        "e2e model",
        &mut ask,
    )
    .unwrap();
    assert!(matches!(again, Outcome::Idle));
}

fn summary_fields_for_probe() -> Value {
    json!({
        "cacheKey": string("probe"),
        "text": string("text"),
        "model": string("m"),
        "source": string("local"),
        "generatedAt": string(&iso(now_ms())),
        "authorUid": string("stranger-uid"),
        "updatedAt": string(&iso(now_ms())),
        "updatedAtTs": spectrum_relay::firestore::timestamp(&iso(now_ms())),
    })
}
