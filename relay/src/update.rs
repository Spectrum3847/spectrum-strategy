use crate::config::Dirs;
use crate::llama::download;
use crate::service::{Event, Shared};
use crate::timeutil::now_ms;
use crate::{autostart, config};
use ring::signature::{ED25519, UnparsedPublicKey};
use serde_json::{Value, json};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;

pub const BUILD: Option<&str> = option_env!("RELAY_BUILD");

pub const RESTART_CODE: u8 = 75;

const PUBLIC_KEY: &str = "19d2022fa095a8a07f10c67c9d4f6cf615bf36fff9bdf9c2dae8aea3aeb5ecbd";
const RELEASE_URL: &str =
    "https://github.com/Spectrum3847/spectrum-strategy/releases/download/relay-latest";
const CHECKSUMS: &str = "relay-checksums.txt";
const CHECK_EVERY: Duration = Duration::from_secs(6 * 60 * 60);
const MAX_TEXT: u64 = 64 * 1024;

pub fn current_build() -> Option<u64> {
    BUILD.and_then(|b| b.parse().ok())
}

pub fn base_url() -> String {
    std::env::var("SPECTRUM_RELAY_UPDATE_URL")
        .map(|u| u.trim_end_matches('/').to_string())
        .unwrap_or_else(|_| RELEASE_URL.to_string())
}

pub fn asset_name(os: &str, arch: &str) -> Option<String> {
    let known = matches!(os, "linux" | "macos" | "windows") && matches!(arch, "x86_64" | "aarch64");
    known.then(|| {
        format!(
            "relay-{os}-{arch}{}",
            if os == "windows" { ".exe" } else { "" }
        )
    })
}

#[derive(Debug, PartialEq)]
pub struct Checksums {
    pub build: u64,
    pub files: Vec<(String, String)>,
}

impl Checksums {
    pub fn sha256(&self, name: &str) -> Option<&str> {
        self.files
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, sha)| sha.as_str())
    }
}

pub fn parse_checksums(text: &str) -> Result<Checksums, String> {
    let mut lines = text.lines().filter(|l| !l.trim().is_empty());
    let build = lines
        .next()
        .and_then(|l| l.strip_prefix("build "))
        .and_then(|n| n.trim().parse::<u64>().ok())
        .filter(|n| *n > 0)
        .ok_or("the checksums file does not start with a build number")?;
    let mut files = Vec::new();
    for line in lines {
        let (sha, name) = line
            .split_once(' ')
            .ok_or_else(|| format!("bad checksums line: {line}"))?;
        let name = name.trim_start_matches([' ', '*']);
        let good_sha = sha.len() == 64 && sha.bytes().all(|b| b.is_ascii_hexdigit());
        if !good_sha || name.is_empty() || name.contains(['/', '\\']) {
            return Err(format!("bad checksums line: {line}"));
        }
        files.push((name.to_string(), sha.to_ascii_lowercase()));
    }
    Ok(Checksums { build, files })
}

fn unhex(text: &str) -> Result<Vec<u8>, String> {
    let text = text.trim();
    if !text.len().is_multiple_of(2) || !text.is_ascii() {
        return Err("bad hex".into());
    }
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&text[i..i + 2], 16).map_err(|_| "bad hex".to_string()))
        .collect()
}

pub fn verify_signature(
    public_hex: &str,
    message: &[u8],
    signature_hex: &str,
) -> Result<(), String> {
    let key = unhex(public_hex)?;
    let signature = unhex(signature_hex)?;
    UnparsedPublicKey::new(&ED25519, key)
        .verify(message, &signature)
        .map_err(|_| "the signature does not match".to_string())
}

#[derive(Debug, PartialEq)]
pub enum Decision {
    UpToDate,
    Install { name: String, sha256: String },
}

pub fn decide(current: u64, sums: &Checksums, os: &str, arch: &str) -> Result<Decision, String> {
    if sums.build <= current {
        return Ok(Decision::UpToDate);
    }
    let name = asset_name(os, arch).ok_or_else(|| format!("no relay build for {os} {arch}"))?;
    let sha256 = sums
        .sha256(&name)
        .ok_or_else(|| format!("the release has no {name}"))?
        .to_string();
    Ok(Decision::Install { name, sha256 })
}

fn old_path(target: &Path) -> PathBuf {
    let mut name = target.file_name().unwrap_or_default().to_os_string();
    name.push(".old");
    target.with_file_name(name)
}

pub fn swap(target: &Path, new: &Path, keep_old: bool) -> Result<(), String> {
    let err = |e: std::io::Error| format!("{}: {e}", target.display());
    if !keep_old {
        return fs::rename(new, target).map_err(err);
    }
    let old = old_path(target);
    match fs::remove_file(&old) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(format!("{}: {e}", old.display())),
    }
    let had_target = target.exists();
    if had_target {
        fs::rename(target, &old).map_err(err)?;
    }
    if let Err(e) = fs::rename(new, target) {
        if had_target {
            let _ = fs::rename(&old, target);
        }
        return Err(err(e));
    }
    Ok(())
}

pub fn remove_old(target: &Path) {
    let _ = fs::remove_file(old_path(target));
}

pub fn installed_build(exe: &Path) -> Option<u64> {
    let output = Command::new(exe).arg("version").output().ok()?;
    String::from_utf8_lossy(&output.stdout).trim().parse().ok()
}

fn text_agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(30)))
        .build()
        .into()
}

fn fetch_text(url: &str) -> Result<String, String> {
    let mut response = text_agent()
        .get(url)
        .call()
        .map_err(|e| format!("{url}: {e}"))?;
    response
        .body_mut()
        .with_config()
        .limit(MAX_TEXT)
        .read_to_string()
        .map_err(|e| format!("{url}: {e}"))
}

#[derive(Debug, PartialEq)]
pub enum Checked {
    UpToDate,
    Installed(u64),
}

pub fn check_and_install(
    base: &str,
    public_key: &str,
    current: u64,
    target: &Path,
    progress: &dyn Fn(String),
) -> Result<Checked, String> {
    let text = fetch_text(&format!("{base}/{CHECKSUMS}"))?;
    let signature = fetch_text(&format!("{base}/{CHECKSUMS}.sig"))?;
    verify_signature(public_key, text.as_bytes(), &signature)?;
    let sums = parse_checksums(&text)?;
    let (name, sha256) = match decide(current, &sums, std::env::consts::OS, std::env::consts::ARCH)?
    {
        Decision::UpToDate => return Ok(Checked::UpToDate),
        Decision::Install { name, sha256 } => (name, sha256),
    };
    let new = old_path(target).with_extension("new");
    let result = (|| {
        download(
            &format!("{base}/{name}"),
            &new,
            &sha256,
            "the relay update",
            progress,
            !base.starts_with("https://"),
        )?;
        make_executable(&new)?;
        if installed_build(&new) != Some(sums.build) {
            return Err("the downloaded relay does not report the signed build".into());
        }
        swap(target, &new, cfg!(windows))
    })();
    if result.is_err() {
        let _ = fs::remove_file(&new);
    }
    result?;
    remove_old(target);
    Ok(Checked::Installed(sums.build))
}

fn make_executable(path: &Path) -> Result<(), String> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    }
    let _ = path;
    Ok(())
}

fn last_check_ms(dirs: &Dirs) -> i64 {
    fs::read_to_string(dirs.update_state_file())
        .ok()
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .and_then(|v| v["lastCheckMs"].as_i64())
        .unwrap_or(0)
}

fn record_check(dirs: &Dirs) {
    let _ = config::write_private(
        &dirs.update_state_file(),
        json!({ "lastCheckMs": now_ms() }).to_string().as_bytes(),
    );
}

pub fn due(last_ms: i64, now: i64) -> bool {
    now - last_ms >= CHECK_EVERY.as_millis() as i64 || last_ms > now
}

fn say(shared: &Shared, text: impl Into<String>) {
    let text = text.into();
    shared.update_state(|s| {
        s.update = Some(Event {
            text,
            at_ms: now_ms(),
        })
    });
}

fn service_check(shared: &Shared, manual: bool) {
    let Some(current) = current_build() else {
        return;
    };
    let config = shared.config();
    if !manual && (!config.auto_update || !due(last_check_ms(&shared.dirs), now_ms())) {
        return;
    }
    if !autostart::is_installed() {
        say(
            shared,
            "Not checked: updates need the relay to start at login",
        );
        return;
    }
    let target = match std::env::current_exe() {
        Ok(path) => path,
        Err(e) => return say(shared, format!("Update failed: {e}")),
    };
    let progress = |_: String| {};
    let result = check_and_install(&base_url(), PUBLIC_KEY, current, &target, &progress);
    record_check(&shared.dirs);
    match result {
        Ok(Checked::UpToDate) => say(shared, format!("Up to date, build {current}")),
        Ok(Checked::Installed(build)) => {
            say(shared, format!("Updated to build {build}, restarting"));
            shared.request_restart();
        }
        Err(e) => {
            eprintln!("update failed: {e}");
            say(shared, format!("Update failed: {e}"));
        }
    }
}

pub fn spawn(shared: Arc<Shared>) {
    if let Ok(exe) = std::env::current_exe() {
        remove_old(&exe);
    }
    if current_build().is_none() {
        return;
    }
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(30));
        loop {
            let manual = shared.take_update_request();
            service_check(&shared, manual);
            if shared.restart_requested() {
                return;
            }
            for _ in 0..30 {
                if shared.update_requested() {
                    break;
                }
                std::thread::sleep(Duration::from_secs(10));
            }
        }
    });
}

pub fn run_now(dirs: &Dirs) -> Result<String, String> {
    let Some(current) = current_build() else {
        return Ok("This is a development build. It does not update itself.".into());
    };
    let target = std::env::current_exe().map_err(|e| e.to_string())?;
    let progress = |text: String| println!("{text}");
    let checked = check_and_install(&base_url(), PUBLIC_KEY, current, &target, &progress)?;
    record_check(dirs);
    Ok(match checked {
        Checked::UpToDate => format!("Up to date, build {current}."),
        Checked::Installed(build) => format!("Updated to build {build}."),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llama::hex;
    use ring::signature::{Ed25519KeyPair, KeyPair};

    const SUM_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("relay-upd-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn picks_the_asset_for_each_platform() {
        assert_eq!(asset_name("linux", "x86_64").unwrap(), "relay-linux-x86_64");
        assert_eq!(
            asset_name("linux", "aarch64").unwrap(),
            "relay-linux-aarch64"
        );
        assert_eq!(
            asset_name("macos", "aarch64").unwrap(),
            "relay-macos-aarch64"
        );
        assert_eq!(asset_name("macos", "x86_64").unwrap(), "relay-macos-x86_64");
        assert_eq!(
            asset_name("windows", "x86_64").unwrap(),
            "relay-windows-x86_64.exe"
        );
        assert_eq!(
            asset_name("windows", "aarch64").unwrap(),
            "relay-windows-aarch64.exe"
        );
        assert!(asset_name("freebsd", "x86_64").is_none());
        assert!(asset_name("linux", "riscv64").is_none());
    }

    #[test]
    fn parses_a_checksums_file() {
        let text = format!(
            "build 202611100300\n{SUM_A}  relay-linux-x86_64\n{SUM_A} *relay-windows-x86_64.exe\n"
        );
        let sums = parse_checksums(&text).unwrap();
        assert_eq!(sums.build, 202611100300);
        assert_eq!(sums.sha256("relay-linux-x86_64"), Some(SUM_A));
        assert_eq!(sums.sha256("relay-windows-x86_64.exe"), Some(SUM_A));
        assert_eq!(sums.sha256("relay-macos-aarch64"), None);
    }

    #[test]
    fn rejects_bad_checksums_files() {
        for text in [
            "",
            "relay-linux-x86_64\n",
            "build 0\n",
            "build x\n",
            &format!("build 5\n{SUM_A}\n"),
            "build 5\nabc  relay-linux-x86_64\n",
            &format!("build 5\n{SUM_A}  ../relay-linux-x86_64\n"),
        ] {
            assert!(parse_checksums(text).is_err(), "{text:?}");
        }
    }

    #[test]
    fn verifies_an_openssl_signature() {
        let key = "c45812ae1395f94f74aafc7cd1db89d7b4984789b2882ed3bd184acae478c7a5";
        let sig = "cb9439e5d388010451228372e155c0e4b657a7712ec0b95afbdc8b01c54caec695a907f57c1c50595c5bd061789a332b08370676a904175390946923fc2a1f07";
        verify_signature(key, b"build 1\n", sig).unwrap();
        assert!(verify_signature(key, b"build 2\n", sig).is_err());
        assert!(verify_signature(key, b"build 1\n", &sig[2..]).is_err());
        assert!(verify_signature(key, b"build 1\n", "zz").is_err());
        let other = "19d2022fa095a8a07f10c67c9d4f6cf615bf36fff9bdf9c2dae8aea3aeb5ecbd";
        assert!(verify_signature(other, b"build 1\n", sig).is_err());
    }

    #[test]
    fn the_compiled_in_key_matches_the_signing_key() {
        let sig = "0a84194a345ac048b98221ce595e1a5bfc60fbd2afba7ce76d2f50bcb982fdc0169450c4ce07c7a14f443bff9eac63399849e06ebf1274ca9efc4ecc3cb20707";
        verify_signature(PUBLIC_KEY, b"spectrum-relay key check\n", sig).unwrap();
    }

    #[test]
    fn only_a_higher_build_installs() {
        let text = format!("build 200\n{SUM_A}  relay-linux-x86_64\n");
        let sums = parse_checksums(&text).unwrap();
        assert_eq!(
            decide(200, &sums, "linux", "x86_64").unwrap(),
            Decision::UpToDate
        );
        assert_eq!(
            decide(300, &sums, "linux", "x86_64").unwrap(),
            Decision::UpToDate
        );
        assert_eq!(
            decide(199, &sums, "linux", "x86_64").unwrap(),
            Decision::Install {
                name: "relay-linux-x86_64".into(),
                sha256: SUM_A.into()
            }
        );
        assert!(decide(199, &sums, "linux", "aarch64").is_err());
        assert!(decide(199, &sums, "plan9", "x86_64").is_err());
    }

    #[test]
    fn checks_are_spaced_by_the_interval() {
        let hour = 3_600_000;
        assert!(due(0, 10 * hour));
        assert!(!due(10 * hour, 12 * hour));
        assert!(due(10 * hour, 16 * hour));
        assert!(due(20 * hour, 10 * hour));
    }

    #[test]
    fn swap_replaces_the_target() {
        let dir = temp("swap");
        let (target, new) = (dir.join("relay"), dir.join("relay.new"));
        for keep_old in [false, true] {
            fs::write(&target, "old").unwrap();
            fs::write(&new, "new").unwrap();
            swap(&target, &new, keep_old).unwrap();
            assert_eq!(fs::read_to_string(&target).unwrap(), "new");
            assert!(!new.exists());
            assert_eq!(old_path(&target).exists(), keep_old);
            remove_old(&target);
            assert!(!old_path(&target).exists());
        }
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn swap_with_backup_restores_the_old_file_on_failure() {
        let dir = temp("rollback");
        let target = dir.join("relay.exe");
        fs::write(&target, "old").unwrap();
        fs::write(old_path(&target), "stale").unwrap();
        assert!(swap(&target, &dir.join("missing"), true).is_err());
        assert_eq!(fs::read_to_string(&target).unwrap(), "old");
        fs::remove_dir_all(&dir).unwrap();
    }

    #[cfg(unix)]
    fn serve(files: Vec<(String, Vec<u8>)>) -> String {
        let server = tiny_http::Server::http("127.0.0.1:0").unwrap();
        let base = format!(
            "http://127.0.0.1:{}",
            server.server_addr().to_ip().unwrap().port()
        );
        std::thread::spawn(move || {
            for request in server.incoming_requests() {
                let path = request.url().trim_start_matches('/').to_string();
                let found = files.iter().find(|(n, _)| *n == path);
                let _ = match found {
                    Some((_, body)) => {
                        request.respond(tiny_http::Response::from_data(body.clone()))
                    }
                    None => request
                        .respond(tiny_http::Response::from_string("no").with_status_code(404)),
                };
            }
        });
        base
    }

    #[cfg(unix)]
    fn release(
        keys: &Ed25519KeyPair,
        build: u64,
        binary: &[u8],
        sign_text: Option<&str>,
    ) -> Vec<(String, Vec<u8>)> {
        use sha2::{Digest, Sha256};
        let name = asset_name(std::env::consts::OS, std::env::consts::ARCH).unwrap();
        let text = format!("build {build}\n{}  {name}\n", hex(&Sha256::digest(binary)));
        let signed = sign_text.unwrap_or(&text);
        vec![
            (CHECKSUMS.into(), text.clone().into_bytes()),
            (
                format!("{CHECKSUMS}.sig"),
                hex(keys.sign(signed.as_bytes()).as_ref()).into_bytes(),
            ),
            (name, binary.to_vec()),
        ]
    }

    #[cfg(unix)]
    #[test]
    fn installs_a_signed_newer_build_and_refuses_the_rest() {
        let keys = Ed25519KeyPair::from_seed_unchecked(&[7u8; 32]).unwrap();
        let public = hex(keys.public_key().as_ref());
        let dir = temp("e2e");
        let target = dir.join("relay");
        let script = |build: u64| format!("#!/bin/sh\necho {build}\n").into_bytes();
        let none = |_: String| {};
        let run = |base: &str, current: u64| {
            fs::write(&target, script(current)).unwrap();
            make_executable(&target).unwrap();
            check_and_install(base, &public, current, &target, &none)
        };

        let good = serve(release(&keys, 200, &script(200), None));
        assert_eq!(run(&good, 100), Ok(Checked::Installed(200)));
        assert_eq!(installed_build(&target), Some(200));
        assert_eq!(run(&good, 200), Ok(Checked::UpToDate));
        assert_eq!(run(&good, 300), Ok(Checked::UpToDate));
        assert_eq!(installed_build(&target), Some(300));

        let tampered = serve(release(
            &keys,
            200,
            &script(200),
            Some("build 200\nsomething else\n"),
        ));
        assert!(run(&tampered, 100).unwrap_err().contains("signature"));
        assert_eq!(installed_build(&target), Some(100));

        let mut bad_file = release(&keys, 200, &script(200), None);
        bad_file[2].1 = script(999);
        let swapped = serve(bad_file);
        assert!(run(&swapped, 100).unwrap_err().contains("checksum"));
        assert_eq!(installed_build(&target), Some(100));

        let liar = serve(release(&keys, 200, &script(150), None));
        assert!(run(&liar, 100).unwrap_err().contains("signed build"));
        assert_eq!(installed_build(&target), Some(100));
        assert!(!dir.join("relay.new").exists());

        let wrong_key = Ed25519KeyPair::from_seed_unchecked(&[9u8; 32]).unwrap();
        let forged = serve(release(&wrong_key, 200, &script(200), None));
        assert!(run(&forged, 100).unwrap_err().contains("signature"));
        fs::remove_dir_all(&dir).unwrap();
    }
}
