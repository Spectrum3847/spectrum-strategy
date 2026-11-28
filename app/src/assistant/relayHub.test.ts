import { describe, expect, it, vi } from "vitest";
import { SignalingError } from "./relay";
import { createHubSignaling } from "./relayHub";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });

function setup(respond: (url: string, init: RequestInit) => Response) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFake = vi.fn(
    async (url: string | URL | Request, init?: RequestInit) => {
      calls.push({ url: String(url), init: init ?? {} });
      return respond(String(url), init ?? {});
    },
  );
  const hub = createHubSignaling({
    origin: "https://hub.example",
    token: async () => "id-token",
    fetch: fetchFake as unknown as typeof fetch,
  });
  return { hub, calls };
}

describe("hub signaling", () => {
  it("lists relays with the ID token as a bearer", async () => {
    const { hub, calls } = setup(() =>
      json({
        relays: [
          { relayId: "a", name: "Shop", model: "m", build: "1", busy: false },
          { relayId: "b", busy: true },
          { name: "no id", busy: false },
          { relayId: "c" },
        ],
      }),
    );
    expect(await hub.relays()).toEqual([
      { id: "a", busy: false },
      { id: "b", busy: true },
    ]);
    expect(calls[0]?.url).toBe("https://hub.example/chat/relays");
    expect(calls[0]?.init.headers).toMatchObject({
      Authorization: "Bearer id-token",
    });
  });

  it("fetches ICE servers", async () => {
    const servers = [{ urls: ["stun:a.example"] }];
    const { hub, calls } = setup(() => json({ iceServers: servers }));
    expect(await hub.iceServers()).toEqual(servers);
    expect(calls[0]?.url).toBe("https://hub.example/chat/ice");
  });

  it("posts the offer and returns the answer", async () => {
    const { hub, calls } = setup(() => json({ sdp: "answer" }));
    const signal = new AbortController().signal;
    expect(await hub.offer("r1", "offer", signal)).toBe("answer");
    expect(calls[0]?.url).toBe("https://hub.example/chat/offer");
    expect(calls[0]?.init.method).toBe("POST");
    expect(JSON.parse(String(calls[0]?.init.body))).toEqual({
      relayId: "r1",
      sdp: "offer",
    });
    expect(calls[0]?.init.signal).toBe(signal);
  });

  it.each([
    [404, "That relay is no longer on. Try again."],
    [409, "Relay busy. Try again shortly."],
    [504, "The relay did not answer. Try again."],
    [502, "The relay had an error. Try again shortly."],
    [401, "Sign in again to use the chat."],
    [500, "Could not reach the chat service. Check the connection."],
  ])(
    "maps offer status %i to a lead-facing message",
    async (status, message) => {
      const { hub } = setup(() => json({ error: "x" }, status));
      const error = await hub
        .offer("r", "offer", new AbortController().signal)
        .catch((e: unknown) => e);
      expect(error).toBeInstanceOf(SignalingError);
      expect((error as Error).message).toBe(message);
    },
  );

  it("treats an answer with no SDP as a relay error", async () => {
    const { hub } = setup(() => json({}));
    await expect(
      hub.offer("r", "offer", new AbortController().signal),
    ).rejects.toThrow("The relay had an error. Try again shortly.");
  });

  it("explains a network failure and passes an abort through", async () => {
    const hub = createHubSignaling({
      origin: "https://hub.example",
      token: async () => "t",
      fetch: (async () => {
        throw new TypeError("Failed to fetch");
      }) as unknown as typeof fetch,
    });
    await expect(hub.relays()).rejects.toThrow(
      "Could not reach the chat service. Check the connection.",
    );
    const aborting = createHubSignaling({
      origin: "https://hub.example",
      token: async () => "t",
      fetch: (async () => {
        throw new DOMException("aborted", "AbortError");
      }) as unknown as typeof fetch,
    });
    await expect(
      aborting.offer("r", "o", new AbortController().signal),
    ).rejects.toMatchObject({ name: "AbortError" });
  });

  it("does not call the hub without a signed-in user", async () => {
    const fetchFake = vi.fn();
    const hub = createHubSignaling({
      origin: "https://hub.example",
      token: async () => null,
      fetch: fetchFake as unknown as typeof fetch,
    });
    await expect(hub.relays()).rejects.toThrow("Sign in again");
    expect(fetchFake).not.toHaveBeenCalled();
  });

  it("refuses a malformed list", async () => {
    const { hub } = setup(() => json({ relays: "nope" }));
    await expect(hub.relays()).rejects.toBeInstanceOf(SignalingError);
  });
});
