use crate::answer::answer_from;
use crate::config::ModelSpec;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const RELEASES_URL: &str = "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=10";
const DOWNLOAD_PREFIX: &str = "https://github.com/ggml-org/llama.cpp/releases/download/";

const CHECK_EVERY: Duration = Duration::from_secs(24 * 60 * 60);
const CURRENT_FILE: &str = "current";
const CHECKED_FILE: &str = "checked";
pub const CONTEXT_TOKENS: u32 = 8192;
const MAX_ANSWER_TOKENS: u32 = 1024;
const START_TIMEOUT: Duration = Duration::from_secs(180);
const CHAT_TIMEOUT: Duration = Duration::from_secs(300);

const STREAM_TIMEOUT: Duration = Duration::from_secs(600);

#[derive(Debug, PartialEq)]
pub struct Build {
    pub tag: String,
    pub name: String,
    pub url: String,
    pub sha256: String,
}

pub fn asset_suffix(os: &str, arch: &str) -> Option<&'static str> {
    Some(match (os, arch) {
        ("linux", "x86_64") => "bin-ubuntu-x64.tar.gz",
        ("linux", "aarch64") => "bin-ubuntu-arm64.tar.gz",
        ("macos", "aarch64") => "bin-macos-arm64.tar.gz",
        ("macos", "x86_64") => "bin-macos-x64.tar.gz",
        ("windows", "x86_64") => "bin-win-cpu-x64.zip",
        ("windows", "aarch64") => "bin-win-cpu-arm64.zip",
        _ => return None,
    })
}

pub fn newest_build(releases: &Value, os: &str, arch: &str) -> Option<Build> {
    let suffix = asset_suffix(os, arch)?;
    releases.as_array()?.iter().find_map(|release| {
        if release["draft"].as_bool() == Some(true) {
            return None;
        }
        let tag = release["tag_name"].as_str().filter(|t| {
            !t.is_empty() && t.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.')
        })?;
        let name = format!("llama-{tag}-{suffix}");
        let asset = release["assets"]
            .as_array()?
            .iter()
            .find(|a| a["name"].as_str() == Some(&name))?;
        let sha256 = asset["digest"]
            .as_str()?
            .strip_prefix("sha256:")
            .filter(|h| h.len() == 64 && h.bytes().all(|b| b.is_ascii_hexdigit()))?;
        let url = asset["browser_download_url"]
            .as_str()
            .filter(|u| u.starts_with(DOWNLOAD_PREFIX))?;
        Some(Build {
            tag: tag.into(),
            name,
            url: url.into(),
            sha256: sha256.into(),
        })
    })
}

fn fetch_newest_build() -> Result<Build, String> {
    let (os, arch) = (std::env::consts::OS, std::env::consts::ARCH);
    let releases: Value = download_agent()
        .get(RELEASES_URL)
        .header("Accept", "application/vnd.github+json")
        .call()
        .and_then(|mut r| r.body_mut().with_config().limit(16 << 20).read_json())
        .map_err(|e| format!("could not check llama.cpp releases: {e}"))?;
    newest_build(&releases, os, arch)
        .ok_or_else(|| format!("no llama.cpp build for {os} {arch} in the newest releases"))
}

fn server_name() -> &'static str {
    if cfg!(windows) {
        "llama-server.exe"
    } else {
        "llama-server"
    }
}

fn download_agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(30)))
        .timeout_recv_response(Some(Duration::from_secs(60)))
        .build()
        .into()
}

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn download(
    url: &str,
    dest: &Path,
    sha256: &str,
    label: &str,
    progress: &dyn Fn(String),
    allow_http: bool,
) -> Result<(), String> {
    if !allow_http && !url.starts_with("https://") {
        return Err("downloads must use https".into());
    }
    let part = dest.with_extension("part");
    let result = (|| {
        let mut response = download_agent()
            .get(url)
            .call()
            .map_err(|e| format!("{label}: {e}"))?;
        let total: u64 = response
            .headers()
            .get("content-length")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        let mut reader = response.body_mut().as_reader();
        let mut file = File::create(&part).map_err(|e| format!("{}: {e}", part.display()))?;
        let mut hasher = Sha256::new();
        let mut buffer = vec![0u8; 64 * 1024];
        let (mut done, mut shown) = (0u64, 101u64);
        loop {
            let n = reader
                .read(&mut buffer)
                .map_err(|e| format!("{label}: {e}"))?;
            if n == 0 {
                break;
            }
            hasher.update(&buffer[..n]);
            file.write_all(&buffer[..n])
                .map_err(|e| format!("{}: {e}", part.display()))?;
            done += n as u64;
            let percent = (done * 100).checked_div(total).unwrap_or(done >> 20);
            if percent != shown {
                shown = percent;
                progress(if total > 0 {
                    format!("Downloading {label}, {percent}%")
                } else {
                    format!("Downloading {label}, {percent} MB")
                });
            }
        }
        file.sync_all().map_err(|e| e.to_string())?;
        let got = hex(&hasher.finalize());
        if !sha256.is_empty() && !got.eq_ignore_ascii_case(sha256) {
            return Err(format!("{label}: checksum mismatch (got {got})"));
        }
        fs::rename(&part, dest).map_err(|e| e.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&part);
    }
    result
}

fn find_file(dir: &Path, name: &str) -> Option<PathBuf> {
    for entry in fs::read_dir(dir).ok()?.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if let Some(found) = find_file(&path, name) {
                return Some(found);
            }
        } else if path.file_name().is_some_and(|n| n == name) {
            return Some(path);
        }
    }
    None
}

fn installed_runtime(llama_dir: &Path) -> Option<(String, PathBuf)> {
    let marked = fs::read_to_string(llama_dir.join(CURRENT_FILE))
        .ok()
        .map(|t| t.trim().to_owned());
    let tags = marked.into_iter().chain(
        fs::read_dir(llama_dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.path().is_dir())
            .filter_map(|e| e.file_name().into_string().ok()),
    );
    for tag in tags {
        if let Some(binary) = find_file(&llama_dir.join(&tag), server_name()) {
            return Some((tag, binary));
        }
    }
    None
}

fn checked_recently(llama_dir: &Path) -> bool {
    fs::metadata(llama_dir.join(CHECKED_FILE))
        .and_then(|m| m.modified())
        .ok()
        .and_then(|at| at.elapsed().ok())
        .is_some_and(|age| age < CHECK_EVERY)
}

pub fn ensure_runtime(llama_dir: &Path, progress: &dyn Fn(String)) -> Result<PathBuf, String> {
    let installed = installed_runtime(llama_dir);
    if let Some((_, binary)) = &installed
        && checked_recently(llama_dir)
    {
        return Ok(binary.clone());
    }
    progress("Checking for llama.cpp updates".into());
    fs::create_dir_all(llama_dir).map_err(|e| e.to_string())?;
    let newest = fetch_newest_build();
    if installed.is_some() {

        let _ = fs::write(llama_dir.join(CHECKED_FILE), b"");
    }
    let build = match (newest, installed) {
        (Ok(build), Some((tag, binary))) if build.tag == tag => {
            let _ = fs::write(llama_dir.join(CURRENT_FILE), &tag);
            return Ok(binary);
        }
        (Ok(build), _) => build,
        (Err(_), Some((_, binary))) => return Ok(binary),
        (Err(e), None) => return Err(e),
    };
    install(llama_dir, &build, progress)
}

fn install(llama_dir: &Path, build: &Build, progress: &dyn Fn(String)) -> Result<PathBuf, String> {
    let archive = llama_dir.join(&build.name);
    download(
        &build.url,
        &archive,
        &build.sha256,
        "llama.cpp",
        progress,
        false,
    )?;

    progress("Unpacking llama.cpp".into());
    let staging = llama_dir.join("staging");
    let _ = fs::remove_dir_all(&staging);
    fs::create_dir_all(&staging).map_err(|e| e.to_string())?;
    let status = Command::new("tar")
        .arg("-xf")
        .arg(&archive)
        .arg("-C")
        .arg(&staging)
        .status()
        .map_err(|e| format!("could not run tar: {e}"))?;
    let _ = fs::remove_file(&archive);
    if !status.success() || find_file(&staging, server_name()).is_none() {
        let _ = fs::remove_dir_all(&staging);
        return Err("the llama.cpp archive did not unpack".into());
    }
    let ready = llama_dir.join(&build.tag);
    let _ = fs::remove_dir_all(&ready);
    fs::rename(&staging, &ready).map_err(|e| e.to_string())?;
    fs::write(llama_dir.join(CURRENT_FILE), &build.tag).map_err(|e| e.to_string())?;
    let _ = fs::write(llama_dir.join(CHECKED_FILE), b"");

    for entry in fs::read_dir(llama_dir).into_iter().flatten().flatten() {
        let name = entry.file_name();
        if name != build.tag.as_str() && name != CURRENT_FILE && name != CHECKED_FILE {
            let _ = fs::remove_dir_all(entry.path());
        }
    }
    find_file(&ready, server_name()).ok_or_else(|| "llama-server missing after unpack".into())
}

pub fn ensure_model(
    models_dir: &Path,
    spec: &ModelSpec,
    progress: &dyn Fn(String),
) -> Result<PathBuf, String> {
    let file = models_dir.join(spec.file_name());
    if !file.exists() {
        fs::create_dir_all(models_dir).map_err(|e| e.to_string())?;
        download(&spec.url, &file, &spec.sha256, &spec.name, progress, false)?;
    }
    for entry in fs::read_dir(models_dir).into_iter().flatten().flatten() {
        if entry.path() != file {
            let _ = fs::remove_file(entry.path());
        }
    }
    Ok(file)
}

fn free_port() -> Result<u16, String> {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    listener
        .local_addr()
        .map(|a| a.port())
        .map_err(|e| e.to_string())
}

pub struct Server {
    child: Child,
    pub url: String,
    pub model_file: PathBuf,
    pub last_used: Instant,
}

impl Server {
    pub fn start(
        binary: &Path,
        model_file: &Path,
        log: &Path,
        context: u32,
    ) -> Result<Self, String> {
        let port = free_port()?;
        if let Some(parent) = log.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let log_file = File::create(log).map_err(|e| format!("{}: {e}", log.display()))?;
        let mut command = Command::new(binary);
        command
            .arg("-m")
            .arg(model_file)
            .args(["--host", "127.0.0.1", "--port", &port.to_string()])
            .args([
                "-c",
                &context.to_string(),
                "-np",
                "1",
                "--jinja",
                "--reasoning-budget",
                "0",
            ])
            .stdin(Stdio::null())
            .stdout(log_file.try_clone().map_err(|e| e.to_string())?)
            .stderr(log_file);
        if let (true, Some(dir)) = (cfg!(target_os = "linux"), binary.parent()) {
            let mut paths = vec![dir.to_path_buf()];
            paths.extend(
                std::env::var_os("LD_LIBRARY_PATH")
                    .iter()
                    .flat_map(std::env::split_paths),
            );
            if let Ok(joined) = std::env::join_paths(paths) {
                command.env("LD_LIBRARY_PATH", joined);
            }
        }
        #[cfg(windows)]
        std::os::windows::process::CommandExt::creation_flags(&mut command, 0x0800_0000);
        let child = command
            .spawn()
            .map_err(|e| format!("could not start llama-server: {e}"))?;
        let mut server = Self {
            child,
            url: format!("http://127.0.0.1:{port}"),
            model_file: model_file.to_path_buf(),
            last_used: Instant::now(),
        };
        server.wait_healthy(log)?;
        Ok(server)
    }

    fn wait_healthy(&mut self, log: &Path) -> Result<(), String> {
        let agent: ureq::Agent = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .timeout_global(Some(Duration::from_secs(2)))
            .build()
            .into();
        let deadline = Instant::now() + START_TIMEOUT;
        while Instant::now() < deadline {
            if let Ok(Some(status)) = self.child.try_wait() {
                return Err(format!(
                    "llama-server exited ({status}); see {}",
                    log.display()
                ));
            }
            let health = agent.get(&format!("{}/health", self.url)).call();
            if health.is_ok_and(|r| r.status().as_u16() == 200) {
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(500));
        }
        Err("llama-server did not become ready in time".into())
    }

    pub fn alive(&mut self) -> bool {
        matches!(self.child.try_wait(), Ok(None))
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn request_body(
    model: &str,
    system: Option<&str>,
    prompt: &str,
    max_tokens: u32,
    stream: bool,
) -> Value {
    let mut messages = Vec::new();
    if let Some(system) = system {
        messages.push(json!({ "role": "system", "content": system }));
    }
    messages.push(json!({ "role": "user", "content": prompt }));
    json!({
        "model": model,
        "temperature": 0.1,
        "top_k": 50,
        "repeat_penalty": 1.1,
        "stream": stream,
        "max_tokens": max_tokens,
        "chat_template_kwargs": { "enable_thinking": false },
        "messages": messages,
    })
}

pub fn chat_body(model: &str, system: Option<&str>, prompt: &str) -> Value {
    request_body(model, system, prompt, MAX_ANSWER_TOKENS, false)
}

pub fn chat(
    base_url: &str,
    model: &str,
    system: Option<&str>,
    prompt: &str,
) -> Result<String, String> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .http_status_as_error(false)
        .timeout_global(Some(CHAT_TIMEOUT))
        .build()
        .into();
    let url = format!("{}/v1/chat/completions", base_url.trim_end_matches('/'));
    let mut response = agent
        .post(&url)
        .send_json(chat_body(model, system, prompt))
        .map_err(|e| format!("could not reach the model: {e}"))?;
    let status = response.status().as_u16();
    if status != 200 {
        return Err(format!("model server answered HTTP {status}"));
    }
    let body: Value = response
        .body_mut()
        .read_json()
        .map_err(|e| format!("model server sent bad JSON: {e}"))?;
    answer_from(&body).ok_or_else(|| "model server sent no answer".into())
}

#[derive(Debug, PartialEq)]
pub enum Sse {
    Text(String),
    Done,
    Skip,
}

pub fn parse_sse_line(line: &str) -> Sse {
    let Some(data) = line.strip_prefix("data:") else {
        return Sse::Skip;
    };
    let data = data.trim();
    if data == "[DONE]" {
        return Sse::Done;
    }
    serde_json::from_str::<Value>(data)
        .ok()
        .and_then(|chunk| {
            chunk
                .pointer("/choices/0/delta/content")
                .and_then(Value::as_str)
                .filter(|text| !text.is_empty())
                .map(|text| Sse::Text(text.to_owned()))
        })
        .unwrap_or(Sse::Skip)
}

pub fn chat_stream(
    base_url: &str,
    model: &str,
    system: Option<&str>,
    prompt: &str,
    max_tokens: u32,
    on_text: &mut dyn FnMut(&str) -> bool,
) -> Result<(), String> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .http_status_as_error(false)
        .timeout_global(Some(STREAM_TIMEOUT))
        .build()
        .into();
    let url = format!("{}/v1/chat/completions", base_url.trim_end_matches('/'));
    let mut response = agent
        .post(&url)
        .send_json(request_body(model, system, prompt, max_tokens, true))
        .map_err(|e| format!("could not reach the model: {e}"))?;
    let status = response.status().as_u16();
    if status != 200 {
        return Err(format!("model server answered HTTP {status}"));
    }
    let mut reader = std::io::BufReader::new(response.body_mut().as_reader());
    let mut line = String::new();
    loop {
        line.clear();
        let read = std::io::BufRead::read_line(&mut reader, &mut line)
            .map_err(|e| format!("model stream broke: {e}"))?;
        if read == 0 {
            return Ok(());
        }
        match parse_sse_line(line.trim_end()) {
            Sse::Text(text) => {
                if !on_text(&text) {
                    return Ok(());
                }
            }
            Sse::Done => return Ok(()),
            Sse::Skip => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_text_of_a_stream_line() {
        let line = r#"data: {"choices":[{"delta":{"content":"Hel"}}]}"#;
        assert_eq!(parse_sse_line(line), Sse::Text("Hel".into()));
        assert_eq!(parse_sse_line("data: [DONE]"), Sse::Done);
        for skipped in [
            "",
            ": keep-alive",
            "data: not json",
            r#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
            r#"data: {"choices":[{"delta":{"content":""}}]}"#,
            r#"data: {"choices":[]}"#,
        ] {
            assert_eq!(parse_sse_line(skipped), Sse::Skip, "{skipped}");
        }
    }

    #[test]
    fn a_streamed_body_asks_for_the_stream_and_the_token_limit() {
        let body = request_body("m", Some("sys"), "ask", 300, true);
        assert_eq!(body["stream"], true);
        assert_eq!(body["max_tokens"], 300);
        assert_eq!(body["messages"][0]["role"], "system");
        assert_eq!(body["temperature"], 0.1);
        assert_eq!(chat_body("m", None, "ask")["max_tokens"], MAX_ANSWER_TOKENS);
    }

    fn release(tag: &str, prerelease: bool, assets: Value) -> Value {
        json!({ "tag_name": tag, "draft": false, "prerelease": prerelease, "assets": assets })
    }

    fn asset(tag: &str, suffix: &str, digest: Option<&str>) -> Value {
        let name = format!("llama-{tag}-{suffix}");
        json!({
            "name": name,
            "digest": digest,
            "browser_download_url": format!("{DOWNLOAD_PREFIX}{tag}/{name}"),
        })
    }

    const HASH: &str = "f660bfb47331c476cbbacb4c7e4cde564ea8238083e3c6fe29602cfbbd46685c";

    #[test]
    fn every_target_has_a_build_name() {
        for (os, arch) in [
            ("linux", "x86_64"),
            ("linux", "aarch64"),
            ("macos", "aarch64"),
            ("macos", "x86_64"),
            ("windows", "x86_64"),
            ("windows", "aarch64"),
        ] {
            assert!(asset_suffix(os, arch).is_some(), "{os} {arch}");
        }
        assert!(asset_suffix("freebsd", "x86_64").is_none());
    }

    #[test]
    fn takes_the_newest_build_for_this_platform_and_skips_releases_without_one() {
        let digest = format!("sha256:{HASH}");
        let releases = json!([
            release("v1.0.0", false, json!([])),
            release(
                "b3",
                true,
                json!([asset("b3", "bin-macos-arm64.tar.gz", Some(&digest))])
            ),
            release(
                "b2",
                true,
                json!([asset("b2", "bin-ubuntu-arm64.tar.gz", Some(&digest))])
            ),
            release(
                "b1",
                true,
                json!([asset("b1", "bin-ubuntu-arm64.tar.gz", Some(&digest))])
            ),
        ]);
        let build = newest_build(&releases, "linux", "aarch64").unwrap();
        assert_eq!(build.tag, "b2");
        assert_eq!(build.name, "llama-b2-bin-ubuntu-arm64.tar.gz");
        assert_eq!(build.sha256, HASH);
        assert!(build.url.starts_with(DOWNLOAD_PREFIX));
        assert_eq!(newest_build(&releases, "windows", "x86_64"), None);
    }

    #[test]
    fn skips_drafts_and_builds_without_a_checksum_or_from_elsewhere() {
        let digest = format!("sha256:{HASH}");
        let suffix = "bin-ubuntu-x64.tar.gz";
        let mut draft = release("b4", true, json!([asset("b4", suffix, Some(&digest))]));
        draft["draft"] = json!(true);
        let mut elsewhere = asset("b2", suffix, Some(&digest));
        elsewhere["browser_download_url"] = json!("https://example.com/llama.tar.gz");
        let releases = json!([
            draft,
            release("b3", true, json!([asset("b3", suffix, None)])),
            release("b2", true, json!([elsewhere])),
            release(
                "../b1",
                true,
                json!([asset("../b1", suffix, Some(&digest))])
            ),
        ]);
        assert_eq!(newest_build(&releases, "linux", "x86_64"), None);
    }

    fn fake_install(dir: &Path, tag: &str) -> PathBuf {
        let binary = dir.join(tag).join("bin").join(server_name());
        fs::create_dir_all(binary.parent().unwrap()).unwrap();
        fs::write(&binary, b"").unwrap();
        binary
    }

    #[test]
    fn finds_the_marked_build_and_an_older_unmarked_install() {
        let dir = std::env::temp_dir().join(format!("relay-llama-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let legacy = fake_install(&dir, "b12118");
        assert_eq!(installed_runtime(&dir), Some(("b12118".into(), legacy)));
        let marked = fake_install(&dir, "b12364");
        fs::write(dir.join(CURRENT_FILE), "b12364\n").unwrap();
        assert_eq!(installed_runtime(&dir), Some(("b12364".into(), marked)));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn uses_the_installed_build_without_asking_github_within_a_day() {
        let dir = std::env::temp_dir().join(format!("relay-llama-day-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let binary = fake_install(&dir, "b5");
        fs::write(dir.join(CURRENT_FILE), "b5").unwrap();
        assert!(!checked_recently(&dir));
        fs::write(dir.join(CHECKED_FILE), b"").unwrap();
        assert!(checked_recently(&dir));
        let asked = std::cell::Cell::new(false);
        let path = ensure_runtime(&dir, &|_| asked.set(true)).unwrap();
        assert_eq!(path, binary);
        assert!(!asked.get());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    #[ignore]
    fn installs_the_newest_build_from_github() {
        let dir = std::env::temp_dir().join(format!("relay-llama-live-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let binary = ensure_runtime(&dir, &|_| {}).unwrap();
        let tag = fs::read_to_string(dir.join(CURRENT_FILE)).unwrap();
        assert!(binary.starts_with(dir.join(&tag)));
        assert!(checked_recently(&dir));
        let out = Command::new(&binary).arg("--version").output().unwrap();
        let text = String::from_utf8_lossy(&out.stdout) + String::from_utf8_lossy(&out.stderr);
        assert!(text.contains(tag.trim_start_matches('b')), "{text}");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn chat_body_has_system_then_user() {
        let body = chat_body("m", Some("sys"), "ask");
        assert_eq!(body["messages"][0]["role"], "system");
        assert_eq!(body["messages"][1]["content"], "ask");
        assert_eq!(body["stream"], false);
        assert_eq!(body["temperature"], 0.1);
        assert_eq!(body["top_k"], 50);
        assert_eq!(body["repeat_penalty"], 1.1);
        let bare = chat_body("m", None, "ask");
        assert_eq!(bare["messages"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn refuses_plain_http_downloads() {
        let dir = std::env::temp_dir().join("relay-http-test");
        let err = download("http://x.test/a", &dir.join("a"), "", "a", &|_| {}, false).unwrap_err();
        assert!(err.contains("https"));
    }

    #[test]
    fn hex_encodes_bytes() {
        assert_eq!(hex(&[0, 15, 255]), "000fff");
    }
}
