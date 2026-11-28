export interface SubscriptionDocument {
  id: string;
  uid: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  userAgent: string;
  createdAt: string;
  updatedAt: string;
}

export const subscriptionPath = (id: string) => `pushSubscriptions/${id}`;

export async function subscriptionId(endpoint: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(endpoint),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function subscriptionDocument(
  uid: string,
  subscription: PushSubscriptionJSON,
  userAgent: string,
  nowIso: string,
): Promise<SubscriptionDocument> {
  const { endpoint, keys } = subscription;
  if (!endpoint || !keys?.p256dh || !keys.auth) {
    throw new Error("The browser gave back an incomplete subscription.");
  }
  return {
    id: await subscriptionId(endpoint),
    uid,
    endpoint,
    p256dh: keys.p256dh,
    auth: keys.auth,
    userAgent: userAgent.slice(0, 200),
    createdAt: nowIso,
    updatedAt: nowIso,
  };
}

export function applicationServerKey(base64url: string) {
  const base64 = base64url.replaceAll("-", "+").replaceAll("_", "/");
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}
