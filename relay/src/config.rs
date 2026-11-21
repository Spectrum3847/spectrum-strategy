use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

pub const DEFAULT_PORT: u16 = 47821;

pub const DEFAULT_MODEL_NAME: &str = "LFM3-1.7B Q4_K_M";
pub const DEFAULT_MODEL_URL: &str = "https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/resolve/cd0c74c575b5c416f3011b5b4c298077f26ca8c2/LFM3-1.7B-Q4_K_M.gguf";
pub const DEFAULT_MODEL_SHA256: &str =
    "3793e1e6e2266919d6e015287221b41100175a98eddaba92e111aed3b05c93c4";

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ModelSpec {
    pub name: String,
    pub url: String,

    pub sha256: String,
}

impl Default for ModelSpec {
    fn default() -> Self {
        Self {
            name: DEFAULT_MODEL_NAME.into(),
            url: DEFAULT_MODEL_URL.into(),
            sha256: DEFAULT_MODEL_SHA256.into(),
        }
    }
}

impl ModelSpec {

    pub fn file_name(&self) -> String {
        let path = self.url.split(['?', '#']).next().unwrap_or("");
        let tail = path.rsplit('/').next().unwrap_or("");
        let clean: String = tail
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_'))
            .collect();
        if clean.is_empty() || clean.starts_with('.') {

            let id: String = self.sha256.chars().take(12).collect();
            format!("model-{id}.gguf")
        } else {
            clean
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub enabled: bool,
    pub port: u16,
    pub model: ModelSpec,
    pub auto_update: bool,

    pub relay_id: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            enabled: true,
            port: DEFAULT_PORT,
            model: ModelSpec::default(),
            auto_update: true,
            relay_id: String::new(),
        }
    }
}

pub struct Dirs {
    pub config: PathBuf,
    pub data: PathBuf,
}

impl Dirs {

    pub fn locate() -> Result<Self, String> {
        if let Some(home) = std::env::var_os("SPECTRUM_RELAY_HOME") {
            let home = PathBuf::from(home);
            return Ok(Self {
                config: home.join("config"),
                data: home.join("data"),
            });
        }
        let dirs = directories::ProjectDirs::from("org", "spectrum3847", "spectrum-relay")
            .ok_or("no home directory")?;
        Ok(Self {
            config: dirs.config_dir().to_path_buf(),
            data: dirs.data_dir().to_path_buf(),
        })
    }

    pub fn config_file(&self) -> PathBuf {
        self.config.join("config.json")
    }
    pub fn token_file(&self) -> PathBuf {
        self.config.join("token.json")
    }
    pub fn llama_dir(&self) -> PathBuf {
        self.data.join("llama")
    }
    pub fn models_dir(&self) -> PathBuf {
        self.data.join("models")
    }
    pub fn bin_dir(&self) -> PathBuf {
        self.data.join("bin")
    }
    pub fn installed_exe(&self) -> PathBuf {
        self.bin_dir()
            .join(if cfg!(windows) { "relay.exe" } else { "relay" })
    }
    pub fn update_state_file(&self) -> PathBuf {
        self.data.join("update.json")
    }
    pub fn relay_log(&self) -> PathBuf {
        self.data.join("relay.log")
    }
    pub fn llama_log(&self) -> PathBuf {
        self.data.join("llama-server.log")
    }
}

pub fn new_relay_id() -> String {
    use ring::rand::{SecureRandom, SystemRandom};
    let mut bytes = [0u8; 16];
    SystemRandom::new()
        .fill(&mut bytes)
        .expect("the system random source failed");
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn load(path: &Path) -> Config {
    fs::read_to_string(path)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default()
}

pub fn save(path: &Path, config: &Config) -> Result<(), String> {
    write_private(
        path,
        &serde_json::to_vec_pretty(config).map_err(|e| e.to_string())?,
    )
}

pub fn write_private(path: &Path, bytes: &[u8]) -> Result<(), String> {
    use std::io::Write;
    let err = |e: std::io::Error| format!("{}: {e}", path.display());
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(err)?;
    }
    let tmp = path.with_extension("tmp");
    let mut options = fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
    let mut file = options.open(&tmp).map_err(err)?;
    file.write_all(bytes).map_err(err)?;
    file.sync_all().map_err(err)?;
    fs::rename(&tmp, path).map_err(err)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_name_comes_from_the_url() {
        let spec = ModelSpec::default();
        assert_eq!(spec.file_name(), "LFM3-1.7B-Q4_K_M.gguf");
        let odd = ModelSpec {
            url: "https://x.test/a/b/../c.gguf?download=true".into(),
            ..ModelSpec::default()
        };
        assert_eq!(odd.file_name(), "c.gguf");
        let none = ModelSpec {
            url: "https://x.test/".into(),
            ..ModelSpec::default()
        };
        assert_eq!(
            none.file_name(),
            format!("model-{}.gguf", &DEFAULT_MODEL_SHA256[..12])
        );
    }

    #[test]
    fn missing_or_partial_config_falls_back_to_defaults() {
        let dir = std::env::temp_dir().join(format!("relay-cfg-{}", std::process::id()));
        let path = dir.join("config.json");
        assert_eq!(load(&path), Config::default());
        fs::create_dir_all(&dir).unwrap();
        fs::write(&path, r#"{"enabled":false}"#).unwrap();
        let loaded = load(&path);
        assert!(!loaded.enabled);
        assert_eq!(loaded.port, DEFAULT_PORT);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn relay_ids_are_random_hex() {
        let (a, b) = (new_relay_id(), new_relay_id());
        assert_eq!(a.len(), 32);
        assert!(a.bytes().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(a, b);
    }

    #[cfg(unix)]
    #[test]
    fn private_files_are_owner_only() {
        use std::os::unix::fs::PermissionsExt;
        let dir = std::env::temp_dir().join(format!("relay-perm-{}", std::process::id()));
        let path = dir.join("token.json");
        write_private(&path, b"{}").unwrap();
        let mode = fs::metadata(&path).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600);
        fs::remove_dir_all(&dir).unwrap();
    }
}
