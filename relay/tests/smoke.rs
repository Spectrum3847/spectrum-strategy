use spectrum_relay::answer::{Request, cache_doc_id, looks_like_an_answer, summary_fields};
use spectrum_relay::config::{Dirs, ModelSpec};
use spectrum_relay::llama;

#[test]
#[ignore]
fn fake_request_through_a_real_model() {
    let dirs = Dirs::locate().unwrap();
    let spec = ModelSpec {
        name: std::env::var("SMOKE_MODEL_NAME").unwrap_or_else(|_| "smoke".into()),
        url: std::env::var("SMOKE_MODEL_URL").expect("SMOKE_MODEL_URL"),
        sha256: std::env::var("SMOKE_MODEL_SHA256").unwrap_or_default(),
    };
    let say = |text: String| println!("{text}");
    let binary = llama::ensure_runtime(&dirs.llama_dir(), &say).unwrap();
    let model = llama::ensure_model(&dirs.models_dir(), &spec, &say).unwrap();
    let server = llama::Server::start(&binary, &model, &dirs.llama_log(), 1024).unwrap();

    let key = "comment-digest:smoke:3847";
    let request = Request {
        id: cache_doc_id(key),
        cache_key: key.into(),
        system: Some("You summarise FRC scouting comments in at most three short lines.".into()),
        prompt: "Comments about team 3847:\n- Q5: fast swerve, 4 coral per cycle\n\
                 - Q9: missed the deep climb twice\n- Q12: plays heavy defence\n\
                 - Q14: lost comms for half the match\nSummarise."
            .into(),
        minimum_chars: Some(80),
        coverage: Some(4),
        requested_by: "poster".into(),
        requested_at_ms: 0,
        claimed_by: None,
        claimed_at_ms: None,
    };
    let started = std::time::Instant::now();
    let answer = llama::chat(
        &server.url,
        &spec.name,
        request.system.as_deref(),
        &request.prompt,
    )
    .unwrap();
    println!("answer in {:?}:\n{answer}", started.elapsed());
    assert!(looks_like_an_answer(&answer, request.minimum_chars));
    let doc = summary_fields(&request, &answer, &spec.name, "relay", 1_800_000_000_000);
    assert_eq!(doc["source"]["stringValue"], "local");
}
