import { type Signaling, SignalingError } from "./relay";

interface Hub {
  origin: string;
  token(): Promise<string | null | undefined>;
  fetch?: typeof fetch;
}

const unreachable = "Could not reach the chat service. Check the connection.";

function offerMessage(status: number): string {
  if (status === 404) return "That relay is no longer on. Try again.";
  if (status === 409) return "Relay busy. Try again shortly.";
  if (status === 504) return "The relay did not answer. Try again.";
  if (status === 502) return "The relay had an error. Try again shortly.";
  if (status === 401) return "Sign in again to use the chat.";
  return unreachable;
}

export function createHubSignaling(hub: Hub): Signaling {
  async function request(path: string, init: RequestInit = {}) {
    const token = await hub.token().catch(() => null);
    if (!token) throw new SignalingError(offerMessage(401));
    try {
      return await (hub.fetch ?? fetch)(`${hub.origin}${path}`, {
        ...init,
        headers: { ...init.headers, Authorization: `Bearer ${token}` },
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError")
        throw error;
      throw new SignalingError(unreachable);
    }
  }
  async function read(path: string): Promise<Record<string, unknown>> {
    const response = await request(path);
    if (!response.ok) throw new SignalingError(offerMessage(response.status));
    const body: unknown = await response.json().catch(() => null);
    if (typeof body !== "object" || body === null)
      throw new SignalingError(unreachable);
    return body as Record<string, unknown>;
  }
  return {
    relays: async () => {
      const { relays } = await read("/chat/relays");
      if (!Array.isArray(relays)) throw new SignalingError(unreachable);
      return relays.flatMap((r) =>
        typeof r?.relayId === "string" && typeof r.busy === "boolean"
          ? [{ id: r.relayId, busy: r.busy }]
          : [],
      );
    },
    iceServers: async () => {
      const { iceServers } = await read("/chat/ice");
      if (!Array.isArray(iceServers)) throw new SignalingError(unreachable);
      return iceServers as RTCIceServer[];
    },
    offer: async (relayId, sdp, signal) => {
      const response = await request("/chat/offer", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ relayId, sdp }),
        signal,
      });
      if (!response.ok) throw new SignalingError(offerMessage(response.status));
      const body: unknown = await response.json().catch(() => null);
      const answer = (body as { sdp?: unknown } | null)?.sdp;
      if (typeof answer !== "string" || answer === "")
        throw new SignalingError(offerMessage(502));
      return answer;
    },
  };
}
