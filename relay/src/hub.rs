use rustls::pki_types::ServerName;
use rustls::{ClientConfig, ClientConnection, RootCertStore, StreamOwned};
use std::io::{self, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::Arc;
use std::time::Duration;
use tungstenite::client::IntoClientRequest;
use tungstenite::http::HeaderValue;
use tungstenite::protocol::WebSocketConfig;
use tungstenite::{HandshakeError, Message, WebSocket};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(15);
const WRITE_TIMEOUT: Duration = Duration::from_secs(10);

const MAX_MESSAGE_BYTES: usize = 64 * 1024;

pub trait Hub {
    fn send(&mut self, text: &str) -> Result<(), String>;

    fn recv(&mut self, wait: Duration) -> Result<Option<String>, String>;
    fn close(&mut self);
}

trait Transport: Read + Write + Send {}
impl<T: Read + Write + Send> Transport for T {}

pub struct WsHub {
    socket: WebSocket<Box<dyn Transport>>,

    control: TcpStream,
}

fn tls_config() -> Arc<ClientConfig> {
    let roots = RootCertStore {
        roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
    };
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let config = ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .expect("ring supports the default TLS versions")
        .with_root_certificates(roots)
        .with_no_client_auth();
    Arc::new(config)
}

fn open_tcp(host: &str, port: u16) -> Result<TcpStream, String> {
    let addrs = (host, port)
        .to_socket_addrs()
        .map_err(|e| format!("could not look up {host}: {e}"))?;
    let mut last = format!("{host} has no address");
    for addr in addrs {
        match TcpStream::connect_timeout(&addr, CONNECT_TIMEOUT) {
            Ok(stream) => return Ok(stream),
            Err(e) => last = format!("could not connect to {addr}: {e}"),
        }
    }
    Err(last)
}

pub fn connect(url: &str, bearer: &str) -> Result<WsHub, String> {
    let mut request = url
        .into_client_request()
        .map_err(|e| format!("bad hub URL: {e}"))?;
    let authorization = HeaderValue::from_str(&format!("Bearer {bearer}"))
        .map_err(|_| "the ID token is not a valid header".to_owned())?;
    request.headers_mut().insert("Authorization", authorization);
    let uri = request.uri().clone();
    let secure = uri.scheme_str() == Some("wss");
    let host = uri.host().ok_or("the hub URL has no host")?.to_owned();
    let port = uri.port_u16().unwrap_or(if secure { 443 } else { 80 });

    let tcp = open_tcp(&host, port)?;
    let io_error = |e: io::Error| format!("socket setup failed: {e}");
    tcp.set_nodelay(true).map_err(io_error)?;
    tcp.set_read_timeout(Some(HANDSHAKE_TIMEOUT))
        .map_err(io_error)?;
    tcp.set_write_timeout(Some(WRITE_TIMEOUT))
        .map_err(io_error)?;
    let control = tcp.try_clone().map_err(io_error)?;

    let transport: Box<dyn Transport> = if secure {
        let name =
            ServerName::try_from(host.clone()).map_err(|e| format!("bad hub host {host}: {e}"))?;
        let connection = ClientConnection::new(tls_config(), name)
            .map_err(|e| format!("TLS setup failed: {e}"))?;
        Box::new(StreamOwned::new(connection, tcp))
    } else {
        Box::new(tcp)
    };

    let config = WebSocketConfig::default().max_message_size(Some(MAX_MESSAGE_BYTES));
    let socket = match tungstenite::client::client_with_config(request, transport, Some(config)) {
        Ok((socket, _)) => socket,
        Err(HandshakeError::Failure(tungstenite::Error::Http(response))) => {
            return Err(refused(response.status().as_u16()));
        }
        Err(HandshakeError::Failure(e)) => return Err(format!("hub handshake failed: {e}")),
        Err(HandshakeError::Interrupted(_)) => {
            return Err("the hub did not answer the handshake in time".into());
        }
    };
    Ok(WsHub { socket, control })
}

fn refused(status: u16) -> String {
    match status {
        401 => "the hub refused this account (HTTP 401); an admin adds it to appConfig/relay.uids"
            .into(),
        _ => format!("the hub refused the connection (HTTP {status})"),
    }
}

fn is_timeout(e: &tungstenite::Error) -> bool {
    matches!(
        e,
        tungstenite::Error::Io(io) if matches!(io.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut)
    )
}

impl Hub for WsHub {
    fn send(&mut self, text: &str) -> Result<(), String> {
        self.socket
            .send(Message::text(text))
            .map_err(|e| format!("could not write to the hub: {e}"))
    }

    fn recv(&mut self, wait: Duration) -> Result<Option<String>, String> {
        self.control
            .set_read_timeout(Some(wait))
            .map_err(|e| format!("socket setup failed: {e}"))?;
        match self.socket.read() {
            Ok(Message::Text(text)) => Ok(Some(text.as_str().to_owned())),
            Ok(Message::Close(_)) => {

                let _ = self.socket.flush();
                Err("the hub closed the connection".into())
            }
            Ok(Message::Ping(_)) => {

                let _ = self.socket.flush();
                Ok(None)
            }
            Ok(_) => Ok(None),
            Err(e) if is_timeout(&e) => Ok(None),
            Err(tungstenite::Error::ConnectionClosed | tungstenite::Error::AlreadyClosed) => {
                Err("the hub closed the connection".into())
            }
            Err(e) => Err(format!("could not read from the hub: {e}")),
        }
    }

    fn close(&mut self) {
        let _ = self.socket.close(None);
        let _ = self.socket.flush();
    }
}
