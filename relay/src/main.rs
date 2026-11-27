use serde_json::Value;
use spectrum_relay::config::{self, Dirs};
use spectrum_relay::{auth, autostart, gui, p2p, service, setup, update};
use std::process::{Command, ExitCode};
use std::time::Duration;

const HELP: &str =
    "relay: answers Spectrum Strategy AI summaries and private chat with a local model

Usage: relay [command]

With no command the relay sets itself up: it copies itself to a permanent
folder, turns on start at login, starts, and opens the settings page.

  run         Run the service and the settings page (what auto start runs)
  gui         Open the settings page in a browser
  status      Show whether the relay is running and what it is doing
  install     Turn the relay on, start it now and at every login
  uninstall   Turn the relay off, stop it and remove auto start
  update      Check for a newer build now and install it
  version     Print the build number
  help        Show this text
";

fn fetch_status(port: u16) -> Option<Value> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(3)))
        .build()
        .into();
    let mut response = agent
        .get(&format!("http://127.0.0.1:{port}/api/status"))
        .call()
        .ok()?;
    response.body_mut().read_json().ok()
}

fn run(dirs: Dirs) -> Result<ExitCode, String> {
    let shared = service::Shared::new(dirs);
    let port = shared.config().port;
    let server = match gui::bind(port) {
        Ok(server) => server,
        Err(_) if fetch_status(port).is_some() => {
            println!("The relay is already running at {}", gui::url(port));
            return Ok(ExitCode::SUCCESS);
        }
        Err(e) => return Err(format!("could not listen on 127.0.0.1:{port}: {e}")),
    };
    println!("Settings page: {}", gui::url(port));
    let page = shared.clone();
    std::thread::spawn(move || gui::serve(server, page, port));
    update::spawn(shared.clone());
    p2p::spawn(shared.clone());
    let stopper = shared.clone();
    if let Err(e) = ctrlc::set_handler(move || stopper.request_stop()) {
        eprintln!("could not watch for a stop signal: {e}");
    }
    service::run(&shared);
    shared.stop_model();
    Ok(if shared.stopping() {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(update::RESTART_CODE)
    })
}

fn double_click_setup(dirs: &Dirs) -> Result<(), String> {
    let port = config::load(&dirs.config_file()).port;
    let was_running = fetch_status(port).is_some();
    let message = setup::run(dirs, was_running)?;
    println!("{message}");
    println!("Opening the settings page: {}", gui::url(port));
    std::thread::sleep(Duration::from_secs(2));
    open_browser(&gui::url(port));
    Ok(())
}

fn pause_on_windows() {
    if cfg!(windows) {
        println!("Press Enter to close this window.");
        let _ = std::io::stdin().read_line(&mut String::new());
    }
}

fn open_browser(url: &str) {
    let opened = match std::env::consts::OS {
        "macos" => Command::new("open").arg(url).status(),
        "windows" => Command::new("cmd").args(["/C", "start", "", url]).status(),
        _ => Command::new("xdg-open").arg(url).status(),
    };
    if opened.is_err() {
        println!("Open this address in a browser: {url}");
    }
}

fn show_status(dirs: &Dirs) {
    let config = config::load(&dirs.config_file());
    let url = gui::url(config.port);
    let Some(status) = fetch_status(config.port) else {
        let who = auth::load_token(&dirs.token_file()).map(|t| t.email);
        println!("Running: no");
        println!("Turned on: {}", if config.enabled { "yes" } else { "no" });
        println!(
            "Start at login: {}",
            if autostart::is_installed() {
                "yes"
            } else {
                "no"
            }
        );
        println!("Signed in as: {}", who.as_deref().unwrap_or("nobody"));
        println!("Start it with: relay install");
        return;
    };
    let text = |v: &Value| v.as_str().unwrap_or("-").to_string();
    let event = |v: &Value| {
        v["text"]
            .as_str()
            .map_or("none".to_string(), str::to_string)
    };
    println!("Running: yes ({url})");
    println!(
        "Build: {}",
        status["build"].as_str().unwrap_or("development")
    );
    println!(
        "Turned on: {}",
        if status["enabled"] == true {
            "yes"
        } else {
            "no"
        }
    );
    println!(
        "Start at login: {}",
        if status["autostart"] == true {
            "yes"
        } else {
            "no"
        }
    );
    println!(
        "Signed in as: {}",
        status["signedInAs"].as_str().unwrap_or("nobody")
    );
    println!("Doing: {}", text(&status["phase"]));
    println!("Model: {}", text(&status["model"]["name"]));
    println!(
        "llama-server: {}",
        if status["llamaRunning"] == true {
            "running"
        } else {
            "stopped"
        }
    );
    println!("Last answer: {}", event(&status["lastAnswer"]));
    println!("Last error: {}", event(&status["lastError"]));
    let chat = &status["chat"];
    println!(
        "Private chat: {}",
        if chat["online"] == true {
            format!("online, {} open", chat["peers"])
        } else {
            "offline".to_string()
        }
    );
    println!("Last chat error: {}", event(&chat["lastError"]));
}

fn main() -> ExitCode {
    let command = std::env::args().nth(1);
    let double_clicked = command.is_none();
    let command = command.unwrap_or_default();
    if command == "version" {
        println!("{}", update::BUILD.unwrap_or("dev"));
        return ExitCode::SUCCESS;
    }
    let result = Dirs::locate().and_then(|dirs| match command.as_str() {
        "run" => run(dirs),
        "" => double_click_setup(&dirs).map(|()| ExitCode::SUCCESS),
        "update" => {
            let message = update::run_now(&dirs)?;
            println!("{message}");
            let is_service_copy = std::env::current_exe()
                .is_ok_and(|exe| setup::same_file(&exe, &dirs.installed_exe()));
            if message.starts_with("Updated") && is_service_copy && autostart::is_installed() {
                autostart::restart()?;
                println!("Restarted.");
            }
            Ok(ExitCode::SUCCESS)
        }
        "gui" => {
            let port = config::load(&dirs.config_file()).port;
            if fetch_status(port).is_none() {
                println!("The relay is not running. Start it with: relay install");
            }
            open_browser(&gui::url(port));
            Ok(ExitCode::SUCCESS)
        }
        "status" => {
            show_status(&dirs);
            Ok(ExitCode::SUCCESS)
        }
        "install" => {
            let mut settings = config::load(&dirs.config_file());
            settings.enabled = true;
            config::save(&dirs.config_file(), &settings)?;
            let exe = std::env::current_exe().map_err(|e| e.to_string())?;
            let message = autostart::install(&exe, true, &dirs.relay_log())?;
            println!("{message}\nSettings page: {}", gui::url(settings.port));
            Ok(ExitCode::SUCCESS)
        }
        "uninstall" => {
            let mut settings = config::load(&dirs.config_file());
            settings.enabled = false;
            config::save(&dirs.config_file(), &settings)?;
            println!("{}", autostart::uninstall(true)?);
            Ok(ExitCode::SUCCESS)
        }
        _ => {
            print!("{HELP}");
            Ok(ExitCode::SUCCESS)
        }
    });
    match result {
        Ok(code) => code,
        Err(e) => {
            eprintln!("error: {e}");
            if double_clicked {
                pause_on_windows();
            }
            ExitCode::FAILURE
        }
    }
}
