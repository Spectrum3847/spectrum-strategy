import type { AssistantRequest } from "./queue";

export interface Relay {
  id: string;
  busy: boolean;
}
export interface Signaling {
  relays(): Promise<Relay[]>;
  iceServers(): Promise<RTCIceServer[]>;
  offer(relayId: string, sdp: string, signal: AbortSignal): Promise<string>;
}
export class SignalingError extends Error {}
export type ChatEvent =
  | { type: "connecting" }
  | { type: "waiting" }
  | { type: "chunk"; text: string }
  | { type: "done"; model: string }
  | { type: "error"; message: string };

export const connectTimeoutMs = 25_000;
const unreachable =
  "Could not reach a relay directly. Try another network, or wait for a relay on this network.";

export function createRelayChat(
  signaling: Signaling,
  peer: (iceServers: RTCIceServer[]) => RTCPeerConnection = (iceServers) =>
    new RTCPeerConnection({ iceServers }),
) {
  let connection: RTCPeerConnection | undefined;
  let channel: RTCDataChannel | undefined;
  let current: { id: string; emit: (event: ChatEvent) => void } | undefined;
  let generation = 0;
  let cleanup: (() => void) | undefined;

  function close() {
    generation++;
    cleanup?.();
    cleanup = undefined;
    channel?.close();
    connection?.close();
    channel = undefined;
    connection = undefined;
  }
  function cancel() {
    if (current && channel?.readyState === "open")
      channel.send(JSON.stringify({ type: "cancel", id: current.id }));
    current = undefined;
    if (channel?.readyState !== "open") close();
  }
  async function ask(
    request: AssistantRequest,
    emit: (event: ChatEvent) => void,
  ) {
    cancel();
    const id = crypto.randomUUID();
    current = { id, emit };
    const version = generation;
    const fail = (message: string) => {
      if (current?.id !== id) return;
      current = undefined;
      close();
      emit({ type: "error", message });
    };
    try {
      if (channel?.readyState !== "open") {
        emit({ type: "connecting" });
        const relays = await signaling.relays();
        if (generation !== version || current?.id !== id) return;
        const relay = relays.find((r) => !r.busy);
        if (!relay) {
          fail(
            relays.length > 0
              ? "Relay busy. Try again shortly."
              : "No relay available.",
          );
          return;
        }
        const iceServers = await signaling.iceServers();
        if (generation !== version || current?.id !== id) return;
        const pc = peer(iceServers);
        connection = pc;
        const dc = pc.createDataChannel("chat", { ordered: true });
        channel = dc;
        dc.onmessage = (event) => {
          if (channel !== dc) return;
          try {
            const msg = JSON.parse(String(event.data)) as {
              type?: string;
              id?: string;
              text?: string;
              model?: string;
              message?: string;
            };
            if (!current || msg.id !== current.id) return;
            if (msg.type === "chunk" && typeof msg.text === "string")
              current.emit({ type: "chunk", text: msg.text });
            else if (msg.type === "done") {
              const turn = current;
              current = undefined;
              turn.emit({ type: "done", model: msg.model ?? "unknown" });
            } else if (msg.type === "error" || msg.type === "cancel") {
              const turn = current;
              current = undefined;
              turn.emit({
                type: "error",
                message:
                  msg.type === "cancel"
                    ? "The relay canceled the question."
                    : msg.message === "busy"
                      ? "Relay busy. Try again shortly."
                      : (msg.message ?? "The relay could not answer."),
              });
            }
          } catch {
          }
        };
        dc.onclose = () => {
          if (channel !== dc) return;
          const turn = current;
          current = undefined;
          close();
          turn?.emit({
            type: "error",
            message: "Connection to the relay closed.",
          });
        };
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await new Promise<void>((resolve) => {
          if (pc.iceGatheringState === "complete") return resolve();
          const timer = setTimeout(done, 5000);
          function done() {
            clearTimeout(timer);
            pc.removeEventListener("icegatheringstatechange", changed);
            resolve();
          }
          function changed() {
            if (pc.iceGatheringState === "complete") done();
          }
          pc.addEventListener("icegatheringstatechange", changed);
        });
        if (generation !== version || current?.id !== id) return;
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), connectTimeoutMs);
        cleanup = () => {
          clearTimeout(timer);
          controller.abort();
        };
        let answer: string;
        try {
          answer = await signaling.offer(
            relay.id,
            pc.localDescription?.sdp ?? "",
            controller.signal,
          );
        } catch (error) {
          if (error instanceof DOMException && error.name === "AbortError")
            throw new Error("The relay did not answer. Try again.");
          throw error;
        } finally {
          clearTimeout(timer);
        }
        if (generation !== version || current?.id !== id) return;
        await new Promise<void>((resolve, reject) => {
          const wait = setTimeout(
            () => reject(new Error(unreachable)),
            connectTimeoutMs,
          );
          cleanup = () => {
            clearTimeout(wait);
            reject(new Error("Canceled"));
          };
          dc.onopen = () => {
            clearTimeout(wait);
            cleanup = undefined;
            resolve();
          };
          pc.setRemoteDescription({ type: "answer", sdp: answer }).catch(
            reject,
          );
        });
      }
      if (generation !== version || current?.id !== id) return;
      emit({ type: "waiting" });
      channel?.send(
        JSON.stringify({
          type: "ask",
          id,
          system: request.system,
          prompt: request.prompt,
          maxTokens: 2048,
        }),
      );
    } catch (error) {
      fail(
        error instanceof Error
          ? error.message
          : "Could not connect to a relay.",
      );
    }
  }
  return { ask, cancel, close };
}
export type RelayChat = ReturnType<typeof createRelayChat>;
