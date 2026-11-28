import { describe, expect, it, vi } from "vitest";
import { type ClientDeps, createClient } from "./client";

const origin = "https://w.example.workers.dev";

function setup(over: Partial<ClientDeps> = {}) {
  const fetchMock = vi.fn<typeof fetch>();
  const client = createClient({
    origin: async () => origin,
    token: async () => "id-token",
    online: () => true,
    fetch: fetchMock,
    ...over,
  });
  return { client, fetchMock };
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status });

describe("upload", () => {
  it("posts the bytes with the ID token and returns the key", async () => {
    const { client, fetchMock } = setup();
    fetchMock.mockResolvedValue(json(201, { key: "k.jpg" }));
    const blob = new Blob(["abc"], { type: "image/jpeg" });
    expect(await client.upload(blob)).toEqual({
      type: "response",
      status: 201,
      key: "k.jpg",
    });
    const [url, init] = fetchMock.mock.calls[0] ?? [];
    expect(url).toBe(`${origin}/photos`);
    expect(init?.method).toBe("POST");
    expect(init?.redirect).toBe("error");
    expect(init?.body).toBe(blob);
    expect(init?.headers).toMatchObject({
      Authorization: "Bearer id-token",
      "Content-Type": "image/jpeg",
    });
  });

  it("reports a refusal by its status", async () => {
    const { client, fetchMock } = setup();
    fetchMock.mockResolvedValue(json(413, { error: "Image too large" }));
    expect(await client.upload(new Blob(["x"]))).toEqual({
      type: "response",
      status: 413,
    });
  });

  it("reports a reply with no key as a server problem", async () => {
    const { client, fetchMock } = setup();
    fetchMock.mockResolvedValue(json(201, {}));
    expect(await client.upload(new Blob(["x"]))).toMatchObject({
      status: 502,
    });
  });

  it("reports a failed request as a network problem", async () => {
    const { client, fetchMock } = setup();
    fetchMock.mockRejectedValue(new TypeError("Failed to fetch"));
    expect(await client.upload(new Blob(["x"]))).toEqual({ type: "network" });
  });

  it("does not call the Worker when offline, signed out or not set up", async () => {
    const offline = setup({ online: () => false });
    expect(await offline.client.upload(new Blob(["x"]))).toEqual({
      type: "unavailable",
      reason: "offline",
    });
    const unset = setup({ origin: async () => null });
    expect(await unset.client.upload(new Blob(["x"]))).toMatchObject({
      reason: "unconfigured",
    });
    const out = setup({ token: async () => null });
    expect(await out.client.upload(new Blob(["x"]))).toMatchObject({
      reason: "signed-out",
    });
    for (const s of [offline, unset, out]) {
      expect(s.fetchMock).not.toHaveBeenCalled();
    }
  });
});

describe("download and remove", () => {
  it("fetches a photo by its encoded key", async () => {
    const { client, fetchMock } = setup();
    fetchMock.mockResolvedValue(new Response("bytes", { status: 200 }));
    const result = await client.download("a b.jpg");
    expect(result.type).toBe("ok");
    expect(fetchMock.mock.calls[0]?.[0]).toBe(`${origin}/photos/a%20b.jpg`);
    expect(fetchMock.mock.calls[0]?.[1]?.headers).toMatchObject({
      Authorization: "Bearer id-token",
    });
  });

  it("says why a photo could not be loaded", async () => {
    const { client, fetchMock } = setup();
    fetchMock.mockResolvedValue(new Response("", { status: 404 }));
    expect(await client.download("k.jpg")).toEqual({ type: "failed" });
    fetchMock.mockResolvedValue(new Response("", { status: 401 }));
    expect(await client.download("k.jpg")).toEqual({
      type: "unavailable",
      reason: "signed-out",
    });
    fetchMock.mockRejectedValue(new TypeError("offline"));
    expect(await client.download("k.jpg")).toEqual({ type: "failed" });
    const offline = setup({ online: () => false });
    expect(await offline.client.download("k.jpg")).toEqual({
      type: "unavailable",
      reason: "offline",
    });
  });

  it("counts a 204 and a 404 as deleted", async () => {
    const { client, fetchMock } = setup();
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 204 }));
    expect(await client.remove("k.jpg")).toBe(true);
    fetchMock.mockResolvedValueOnce(new Response("", { status: 404 }));
    expect(await client.remove("k.jpg")).toBe(true);
    expect(fetchMock.mock.calls[0]?.[1]?.method).toBe("DELETE");
    fetchMock.mockResolvedValueOnce(new Response("", { status: 403 }));
    expect(await client.remove("k.jpg")).toBe(false);
    fetchMock.mockRejectedValueOnce(new TypeError("offline"));
    expect(await client.remove("k.jpg")).toBe(false);
  });
});
