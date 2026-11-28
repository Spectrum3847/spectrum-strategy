import { describe, expect, it } from "vitest";
import {
  applicationServerKey,
  subscriptionDocument,
  subscriptionId,
  subscriptionPath,
} from "./subscription";

const json = {
  endpoint: "https://fcm.googleapis.com/fcm/send/abc",
  keys: { p256dh: "BKey", auth: "authSecret" },
};

describe("subscriptionId", () => {
  it("is the SHA-256 hex of the endpoint", async () => {
    expect(await subscriptionId("abc")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });

  it("is the same for the same endpoint, so a second save is one document", async () => {
    expect(await subscriptionId(json.endpoint)).toBe(
      await subscriptionId(json.endpoint),
    );
  });
});

describe("subscriptionDocument", () => {
  it("has exactly the fields the rules allow", async () => {
    const doc = await subscriptionDocument(
      "u1",
      json,
      "Chrome on Android",
      "2026-11-10T18:00:00.000Z",
    );
    expect(Object.keys(doc).sort()).toEqual(
      [
        "auth",
        "createdAt",
        "endpoint",
        "id",
        "p256dh",
        "uid",
        "updatedAt",
        "userAgent",
      ].sort(),
    );
    expect(doc).toMatchObject({
      uid: "u1",
      endpoint: json.endpoint,
      p256dh: "BKey",
      auth: "authSecret",
      createdAt: "2026-11-10T18:00:00.000Z",
      updatedAt: "2026-11-10T18:00:00.000Z",
    });
    expect(doc.id).toBe(await subscriptionId(json.endpoint));
    expect(subscriptionPath(doc.id)).toBe(`pushSubscriptions/${doc.id}`);
  });

  it("caps the user agent at the rules' 200 characters", async () => {
    const doc = await subscriptionDocument(
      "u1",
      json,
      "x".repeat(500),
      "2026-11-10T18:00:00.000Z",
    );
    expect(doc.userAgent).toHaveLength(200);
  });

  it("refuses a subscription with no keys", async () => {
    await expect(
      subscriptionDocument("u1", { endpoint: json.endpoint }, "", "now"),
    ).rejects.toThrow(/incomplete/);
  });
});

describe("applicationServerKey", () => {
  it("decodes the public key to a 65-byte uncompressed point", () => {
    const key = applicationServerKey(
      "BOucdc9DnIIOu7Pwvw7JZzwT645RdQcl06b-a2wOTOZ6rp7m2wgo92BvR_zHoqtoYGYBxWyhqdzpYChfSwQyyso",
    );
    expect(key).toHaveLength(65);
    expect(key[0]).toBe(4);
  });
});
