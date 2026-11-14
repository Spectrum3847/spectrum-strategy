use crate::config::{self, Dirs};
use crate::{autostart, update};
use std::fs;
use std::path::Path;

pub fn same_file(a: &Path, b: &Path) -> bool {
    match (fs::canonicalize(a), fs::canonicalize(b)) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    }
}

pub fn place(exe: &Path, target: &Path) -> Result<bool, String> {
    if same_file(exe, target) {
        return Ok(false);
    }
    let versions = (update::installed_build(target), update::current_build());
    if matches!(versions, (Some(installed), Some(mine)) if installed >= mine) {
        return Ok(false);
    }
    let err = |e: std::io::Error| format!("{}: {e}", target.display());
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(err)?;
    }
    let staged = target.with_extension("new");
    fs::copy(exe, &staged).map_err(err)?;
    #[cfg(target_os = "macos")]
    if let Err(e) = unquarantine(&staged) {
        let _ = fs::remove_file(&staged);
        return Err(e);
    }
    if let Err(e) = update::swap(target, &staged, cfg!(windows)) {
        let _ = fs::remove_file(&staged);
        return Err(e);
    }
    update::remove_old(target);
    Ok(true)
}

#[cfg(target_os = "macos")]
fn unquarantine(path: &Path) -> Result<(), String> {
    let out = std::process::Command::new("xattr")
        .args(["-d", "com.apple.quarantine"])
        .arg(path)
        .output()
        .map_err(|e| format!("could not run xattr on {}: {e}", path.display()))?;
    let stderr = String::from_utf8_lossy(&out.stderr);
    if out.status.success() || stderr.contains("No such xattr") {
        return Ok(());
    }
    Err(format!(
        "could not clear the quarantine flag on {}: {}",
        path.display(),
        stderr.trim()
    ))
}

pub fn run(dirs: &Dirs, was_running: bool) -> Result<String, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let target = dirs.installed_exe();
    let replaced = place(&exe, &target)?;
    let mut settings = config::load(&dirs.config_file());
    settings.enabled = true;
    config::save(&dirs.config_file(), &settings)?;
    let message = autostart::install(&target, true, &dirs.relay_log())?;
    if was_running && replaced {
        autostart::restart()?;
    }
    Ok(message)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("relay-setup-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn copies_the_binary_once() {
        let dir = temp("place");
        let (exe, target) = (dir.join("download"), dir.join("bin").join("relay"));
        fs::write(&exe, "binary").unwrap();
        assert!(place(&exe, &target).unwrap());
        assert_eq!(fs::read_to_string(&target).unwrap(), "binary");
        assert!(!place(&target, &target).unwrap());
        fs::remove_dir_all(&dir).unwrap();
    }
}
