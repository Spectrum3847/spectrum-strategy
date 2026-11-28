import { afterEach, describe, expect, it, vi } from "vitest";
import {
  type ChatEvent,
  connectTimeoutMs,
  createRelayChat,
  type Signaling,
  SignalingError,
} from "./relay";

class FakeChannel {
  readyState = "connecting";
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  send = vi.fn((_data: string) => undefined);
  close() {
    this.readyState = "closed";
  }
  open() {
    this.readyState = "open";
    this.onopen?.();
  }
  message(value: unknown) {
    this.onmessage?.({ data: JSON.stringify(value) });
  }
}
class FakePeer {
  channel = new FakeChannel();
  iceGatheringState = "complete";
  localDescription = { sdp: "offer" };
  createDataChannel = vi.fn(() => this.channel);
  createOffer = vi.fn(async () => ({ type: "offer", sdp: "offer" }));
  setLocalDescription = vi.fn(async () => undefined);
  setRemoteDescription = vi.fn(async () => undefined);
  close = vi.fn();
}
function setup(relays = [{ id: "r", busy: false }]) {
  const pc = new FakePeer();
  const ice = [{ urls: "stun:stun.example:3478" }];
  const offers: { relayId: string; sdp: string; signal: AbortSignal }[] = [];
  let answer: ((sdp: string) => void) | undefined;
  let refuse: ((error: Error) => void) | undefined;
  const signaling: Signaling = {
    relays: vi.fn(async () => relays),
    iceServers: vi.fn(async () => ice),
    offer: vi.fn(
      (relayId, sdp, signal) =>
        new Promise<string>((resolve, reject) => {
          offers.push({ relayId, sdp, signal });
          answer = resolve;
          refuse = reject;
          signal.addEventListener("abort", () =>
            reject(new DOMException("aborted", "AbortError")),
          );
        }),
    ),
  };
  const peer = vi.fn(
    (_ice: RTCIceServer[]) => pc as unknown as RTCPeerConnection,
  );
  const chat = createRelayChat(signaling, peer);
  const events: ChatEvent[] = [];
  const request = {
    cacheKey: "k",
    system: "system",
    prompt: "prompt",
    minimumChars: 10,
  };
  return {
    pc,
    ice,
    peer,
    offers,
    signaling,
    chat,
    events,
    request,
    answer: () => answer?.("answer"),
    refuse: (message: string) => refuse?.(new SignalingError(message)),
  };
}
const flush = async () => {
  for (let i = 0; i < 12; i++) await Promise.resolve();
};
afterEach(() => vi.useRealTimers());
describe("private relay chat", () => {
  it("connects through the hub, streams, and reuses the channel", async () => {
    const t = setup();
    const first = t.chat.ask(t.request, (e) => t.events.push(e));
    await flush();
    expect(t.peer).toHaveBeenCalledWith(t.ice);
    expect(t.offers).toHaveLength(1);
    expect(t.offers[0]).toMatchObject({ relayId: "r", sdp: "offer" });
    t.answer();
    await flush();
    expect(t.pc.setRemoteDescription).toHaveBeenCalledWith({
      type: "answer",
      sdp: "answer",
    });
    t.pc.channel.open();
    await first;
    const sent = JSON.parse(t.pc.channel.send.mock.calls[0]?.[0] as string);
    expect(sent).toMatchObject({
      type: "ask",
      system: "system",
      prompt: "prompt",
      maxTokens: 2048,
    });
    t.pc.channel.message({ type: "chunk", id: sent.id, text: "hello" });
    t.pc.channel.message({ type: "done", id: sent.id, model: "model" });
    expect(t.events).toContainEqual({ type: "chunk", text: "hello" });
    expect(t.events).toContainEqual({ type: "done", model: "model" });
    await t.chat.ask(t.request, () => undefined);
    expect(t.offers).toHaveLength(1);
    expect(t.signaling.iceServers).toHaveBeenCalledOnce();
    t.chat.cancel();
    expect(
      JSON.parse(t.pc.channel.send.mock.calls.at(-1)?.[0] as string).type,
    ).toBe("cancel");
  });
  it("closes the peer when the relay drops an idle channel", async () => {
    const t = setup();
    const first = t.chat.ask(t.request, (e) => t.events.push(e));
    await flush();
    t.answer();
    await flush();
    t.pc.channel.open();
    await first;
    const sent = JSON.parse(t.pc.channel.send.mock.calls[0]?.[0] as string);
    t.pc.channel.message({ type: "done", id: sent.id, model: "model" });
    const stale = t.pc.channel.onclose;
    t.pc.channel.readyState = "closed";
    stale?.();
    expect(t.pc.close).toHaveBeenCalled();
    expect(t.events.some((e) => e.type === "error")).toBe(false);
  });
  it("ignores a close from a channel it already replaced", async () => {
    const t = setup();
    const first = t.chat.ask(t.request, () => undefined);
    await flush();
    t.answer();
    await flush();
    t.pc.channel.open();
    await first;
    const stale = t.pc.channel.onclose;
    t.chat.cancel();
    t.pc.channel.readyState = "closed";
    t.pc.channel = new FakeChannel();
    const second = t.chat.ask(t.request, (e) => t.events.push(e));
    await flush();
    stale?.();
    t.answer();
    await flush();
    t.pc.channel.open();
    await second;
    expect(t.events.some((e) => e.type === "error")).toBe(false);
  });
  it("gives up when the channel does not open after the answer", async () => {
    vi.useFakeTimers();
    const t = setup();
    const pending = t.chat.ask(t.request, (e) => t.events.push(e));
    await flush();
    t.answer();
    await flush();
    await vi.advanceTimersByTimeAsync(connectTimeoutMs);
    await pending;
    expect(connectTimeoutMs).toBe(25_000);
    expect(t.pc.close).toHaveBeenCalled();
    expect(t.events.at(-1)).toMatchObject({
      type: "error",
      message: expect.stringContaining("Try another network"),
    });
  });
  it("says the relay did not answer when the offer hangs", async () => {
    vi.useFakeTimers();
    const t = setup();
    const pending = t.chat.ask(t.request, (e) => t.events.push(e));
    await flush();
    await vi.advanceTimersByTimeAsync(connectTimeoutMs);
    await pending;
    expect(t.events.at(-1)).toEqual({
      type: "error",
      message: "The relay did not answer. Try again.",
    });
  });
  it("shows the hub's message when it refuses the offer", async () => {
    const t = setup();
    const pending = t.chat.ask(t.request, (e) => t.events.push(e));
    await flush();
    t.refuse("Relay busy. Try again shortly.");
    await pending;
    expect(t.events.at(-1)).toEqual({
      type: "error",
      message: "Relay busy. Try again shortly.",
    });
    expect(t.pc.close).toHaveBeenCalled();
  });
  it("reports no available relay and a busy relay", async () => {
    const absent = setup([]);
    await absent.chat.ask(absent.request, (e) => absent.events.push(e));
    expect(absent.events.at(-1)).toEqual({
      type: "error",
      message: "No relay available.",
    });
    expect(absent.signaling.iceServers).not.toHaveBeenCalled();
    const busy = setup([{ id: "r", busy: true }]);
    await busy.chat.ask(busy.request, (e) => busy.events.push(e));
    expect(busy.events.at(-1)).toEqual({
      type: "error",
      message: "Relay busy. Try again shortly.",
    });
  });
  it("picks a relay that is not busy", async () => {
    const t = setup([
      { id: "busy", busy: true },
      { id: "free", busy: false },
    ]);
    void t.chat.ask(t.request, (e) => t.events.push(e));
    await flush();
    expect(t.offers[0]?.relayId).toBe("free");
    t.chat.cancel();
  });
  it("aborts the offer when canceled while connecting", async () => {
    const t = setup();
    const pending = t.chat.ask(t.request, (e) => t.events.push(e));
    await flush();
    t.chat.cancel();
    await pending;
    expect(t.offers[0]?.signal.aborted).toBe(true);
    expect(t.events.some((e) => e.type === "error")).toBe(false);
  });
});
