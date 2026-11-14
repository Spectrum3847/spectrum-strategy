use std::path::{Path, PathBuf};
use std::process::Command;

const UNIT: &str = "spectrum-relay.service";
const LABEL: &str = "org.spectrum3847.spectrumstrategy.relay";
const TASK: &str = "Spectrum Strategy AI relay";

pub fn systemd_unit(exe: &Path) -> String {
    format!(
        "[Unit]\nDescription=Spectrum Strategy AI relay\nAfter=network-online.target\n\n\
         [Service]\nExecStart=\"{}\" run\nRestart=on-failure\nRestartSec=10\nNice=10\n\n\
         [Install]\nWantedBy=default.target\n",
        exe.display()
    )
}

fn xml_escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

pub fn launch_agent_plist(exe: &Path, log: &Path) -> String {
    let (exe, log) = (
        xml_escape(&exe.to_string_lossy()),
        xml_escape(&log.to_string_lossy()),
    );
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
         <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
         <plist version=\"1.0\">\n<dict>\n\
         \t<key>Label</key><string>{LABEL}</string>\n\
         \t<key>ProgramArguments</key><array><string>{exe}</string><string>run</string></array>\n\
         \t<key>RunAtLoad</key><true/>\n\
         \t<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>\n\
         \t<key>ProcessType</key><string>Background</string>\n\
         \t<key>StandardOutPath</key><string>{log}</string>\n\
         \t<key>StandardErrorPath</key><string>{log}</string>\n\
         </dict>\n</plist>\n"
    )
}

pub fn windows_task_command(exe: &Path) -> String {
    let exe = exe.to_string_lossy().replace('\'', "''");
    format!(
        "powershell.exe -NoP -W Hidden -C \"do {{ & '{exe}' run; $c=$LASTEXITCODE; if ($c -notin 0,75) {{ sleep 10 }} }} while ($c)\""
    )
}

fn run(program: &str, args: &[&str]) -> Result<(), String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|e| format!("could not run {program}: {e}"))?;
    if output.status.success() {
        return Ok(());
    }
    let detail = String::from_utf8_lossy(&output.stderr);
    Err(format!("{program} {}: {}", args.join(" "), detail.trim()))
}

fn home() -> Result<PathBuf, String> {
    directories::BaseDirs::new()
        .map(|d| d.home_dir().to_path_buf())
        .ok_or_else(|| "no home directory".into())
}

fn unit_path() -> Result<PathBuf, String> {
    Ok(home()?.join(".config/systemd/user").join(UNIT))
}

fn plist_path() -> Result<PathBuf, String> {
    Ok(home()?
        .join("Library/LaunchAgents")
        .join(format!("{LABEL}.plist")))
}

fn write(path: &Path, text: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(path, text).map_err(|e| format!("{}: {e}", path.display()))
}

fn uid() -> String {
    Command::new("id")
        .arg("-u")
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

pub fn install(exe: &Path, start_now: bool, log: &Path) -> Result<String, String> {
    match std::env::consts::OS {
        "linux" => {
            write(&unit_path()?, &systemd_unit(exe))?;
            run("systemctl", &["--user", "daemon-reload"])?;
            if start_now {
                run("systemctl", &["--user", "enable", "--now", UNIT])?;
            } else {
                run("systemctl", &["--user", "enable", UNIT])?;
            }

            let linger = run("loginctl", &["enable-linger"]);
            Ok(match linger {
                Ok(()) => "Starts at boot.".into(),
                Err(_) => "Starts at login. For boot without a login, run: sudo loginctl enable-linger $USER".into(),
            })
        }
        "macos" => {
            write(&plist_path()?, &launch_agent_plist(exe, log))?;
            if start_now {
                let domain = format!("gui/{}", uid());
                let plist = plist_path()?;

                let _ = run(
                    "launchctl",
                    &["bootstrap", &domain, &plist.to_string_lossy()],
                );
            }
            Ok("Starts at login.".into())
        }
        "windows" => {
            let command = windows_task_command(exe);
            run(
                "schtasks",
                &[
                    "/Create", "/TN", TASK, "/TR", &command, "/SC", "ONLOGON", "/RL", "LIMITED",
                    "/F",
                ],
            )?;
            if start_now {
                run("schtasks", &["/Run", "/TN", TASK])?;
            }
            Ok("Starts at login.".into())
        }
        other => Err(format!("auto start is not supported on {other}")),
    }
}

pub fn restart() -> Result<(), String> {
    match std::env::consts::OS {
        "linux" => run("systemctl", &["--user", "restart", UNIT]),
        "macos" => run(
            "launchctl",
            &["kickstart", "-k", &format!("gui/{}/{LABEL}", uid())],
        ),
        "windows" => {
            let _ = run("schtasks", &["/End", "/TN", TASK]);
            run("schtasks", &["/Run", "/TN", TASK])
        }
        other => Err(format!("auto start is not supported on {other}")),
    }
}

pub fn uninstall(stop_now: bool) -> Result<String, String> {
    match std::env::consts::OS {
        "linux" => {
            let path = unit_path()?;
            if path.exists() {
                let args: &[&str] = if stop_now {
                    &["--user", "disable", "--now", UNIT]
                } else {
                    &["--user", "disable", UNIT]
                };
                run("systemctl", args)?;
                std::fs::remove_file(&path).map_err(|e| e.to_string())?;
                run("systemctl", &["--user", "daemon-reload"])?;
            }
        }
        "macos" => {
            if stop_now {
                let target = format!("gui/{}/{LABEL}", uid());
                let _ = run("launchctl", &["bootout", &target]);
            }
            let path = plist_path()?;
            if path.exists() {
                std::fs::remove_file(&path).map_err(|e| e.to_string())?;
            }
        }
        "windows" => {
            if stop_now {
                let _ = run("schtasks", &["/End", "/TN", TASK]);
            }
            if is_installed() {
                run("schtasks", &["/Delete", "/TN", TASK, "/F"])?;
            }
        }
        other => return Err(format!("auto start is not supported on {other}")),
    }
    Ok("Does not start at login.".into())
}

pub fn is_installed() -> bool {
    match std::env::consts::OS {
        "linux" => unit_path().is_ok_and(|p| p.exists()),
        "macos" => plist_path().is_ok_and(|p| p.exists()),
        "windows" => run("schtasks", &["/Query", "/TN", TASK]).is_ok(),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unit_runs_the_relay_and_restarts_on_failure() {
        let unit = systemd_unit(Path::new("/home/u/bin/relay"));
        assert!(unit.contains("ExecStart=\"/home/u/bin/relay\" run"));
        assert!(unit.contains("Restart=on-failure"));
        assert!(unit.contains("WantedBy=default.target"));
    }

    #[test]
    fn plist_escapes_paths() {
        let plist = launch_agent_plist(Path::new("/Apps/A&B/relay"), Path::new("/tmp/log"));
        assert!(plist.contains("/Apps/A&amp;B/relay"));
        assert!(plist.contains(LABEL));
        assert!(plist.contains("<key>RunAtLoad</key><true/>"));
    }

    #[test]
    fn windows_command_quotes_the_path() {
        let command = windows_task_command(Path::new(r"C:\Users\O'Neil\relay.exe"));
        assert!(command.contains(r"'C:\Users\O''Neil\relay.exe' run"));
        assert!(command.contains("-W Hidden"));
        assert!(command.contains("if ($c -notin 0,75) { sleep 10 }"));
        assert!(command.ends_with("while ($c)\""));
    }

    #[test]
    fn windows_command_fits_schtasks() {
        let long = format!(
            r"C:\Users\{}\AppData\Roaming\spectrum3847\spectrum-relay\data\bin\relay.exe",
            "u".repeat(64)
        );
        assert!(windows_task_command(Path::new(&long)).len() <= 261);
    }
}
