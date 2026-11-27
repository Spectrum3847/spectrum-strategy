pub const DATA_API_KEY: &str = "AIzaSyCgatjO0H0C7pl3Lh0_tfcbFbDV-Xru7yg";
pub const DATA_PROJECT_ID: &str = "frcspectrumstrategy";
pub const DATA_AUTH_DOMAIN: &str = "frcspectrumstrategy.firebaseapp.com";

pub const CENTRAL_API_KEY: &str = "AIzaSyANgQ_R01hyMdoyKQqTPVIHI69GzdedYIE";
pub const CENTRAL_PROJECT_ID: &str = "spectrumtasks-81c63";
pub const CENTRAL_AUTH_DOMAIN: &str = "spectrumtasks-81c63.firebaseapp.com";

pub const APP_KEY: &str = "spectrumstrategy";
pub const CUSTOM_TOKEN_CALLABLE: &str = "getCustomToken";

pub const CHAT_HUB_HOST: &str = "spectrumstrategy-crons.spectrum-3847.workers.dev";
pub const CHAT_HUB_URL: &str = "wss://spectrumstrategy-crons.spectrum-3847.workers.dev/chat/relay";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_the_app_config() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../app/src/firebase/config.ts");
        let Ok(ts) = std::fs::read_to_string(path) else {
            return;
        };
        for value in [
            DATA_API_KEY,
            DATA_PROJECT_ID,
            DATA_AUTH_DOMAIN,
            CENTRAL_API_KEY,
            CENTRAL_PROJECT_ID,
            CENTRAL_AUTH_DOMAIN,
            APP_KEY,
            CUSTOM_TOKEN_CALLABLE,
        ] {
            assert!(
                ts.contains(&format!("\"{value}\"")),
                "{value} not in config.ts"
            );
        }
    }

    #[test]
    fn the_chat_hub_is_the_workers_the_app_calls() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../app/src/push/config.ts");
        let Ok(ts) = std::fs::read_to_string(path) else {
            return;
        };
        assert!(
            ts.contains(CHAT_HUB_HOST),
            "{CHAT_HUB_HOST} not in push/config.ts"
        );
        assert_eq!(CHAT_HUB_URL, format!("wss://{CHAT_HUB_HOST}/chat/relay"));
    }
}
