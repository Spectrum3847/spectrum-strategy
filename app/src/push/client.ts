import { deleteDoc, doc } from "firebase/firestore";
import { dataAuth, db } from "../firebase/client";
import { dismissItem, enqueueWrite, getOutbox } from "../outbox/outbox";
import { pushWorkerOrigin, vapidPublicKey } from "./config";
import { isIos, type PushState, pushState, userAgentSummary } from "./state";
import {
  applicationServerKey,
  subscriptionDocument,
  subscriptionId,
  subscriptionPath,
} from "./subscription";
import { describeTestResponse, type TestAnswer } from "./testRequest";

const serviceWorkerWaitMs = 5_000;

export interface PushStatus {
  state: PushState;
  id: string | null;
}

const hasPush = () =>
  "serviceWorker" in navigator &&
  "PushManager" in window &&
  "Notification" in window;

const standalone = () =>
  (typeof matchMedia === "function" &&
    matchMedia("(display-mode: standalone)").matches) ||
  (navigator as { standalone?: boolean }).standalone === true;

async function currentSubscription() {
  if (!("serviceWorker" in navigator)) return null;
  const registration = await navigator.serviceWorker.getRegistration();
  return (await registration?.pushManager?.getSubscription()) ?? null;
}

export async function readStatus(): Promise<PushStatus> {
  const supported = hasPush();
  const subscription = supported ? await currentSubscription() : null;
  const state = pushState({
    ios: isIos(
      navigator.userAgent,
      navigator.platform,
      navigator.maxTouchPoints,
    ),
    standalone: standalone(),
    hasPush: supported,
    permission: supported ? Notification.permission : "default",
    subscribed: subscription !== null,
  });
  return {
    state,
    id: subscription ? await subscriptionId(subscription.endpoint) : null,
  };
}

async function readyRegistration() {
  const timeout = new Promise<null>((resolve) =>
    setTimeout(() => resolve(null), serviceWorkerWaitMs),
  );
  return Promise.race([navigator.serviceWorker.ready, timeout]);
}

export type TurnOnResult = { ok: true } | { ok: false; message: string };

export async function turnOn(uid: string): Promise<TurnOnResult> {
  const permission = await Notification.requestPermission();
  if (permission !== "granted") {
    return {
      ok: false,
      message:
        permission === "denied"
          ? "Notifications are blocked for this app."
          : "Notifications were not allowed, so reminders stay off.",
    };
  }
  const registration = await readyRegistration();
  if (!registration) {
    return {
      ok: false,
      message: "The app is not ready for notifications yet. Reload and retry.",
    };
  }
  await (await registration.pushManager.getSubscription())?.unsubscribe();
  let subscription: PushSubscription;
  try {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: applicationServerKey(vapidPublicKey),
    });
  } catch (error) {
    return {
      ok: false,
      message: `The browser could not subscribe: ${error instanceof Error ? error.message : "unknown error"}.`,
    };
  }
  try {
    const document = await subscriptionDocument(
      uid,
      subscription.toJSON(),
      userAgentSummary(navigator.userAgent),
      new Date().toISOString(),
    );
    await enqueueWrite(
      subscriptionPath(document.id),
      document,
      "Shift reminders on this device",
    );
  } catch (error) {
    await subscription.unsubscribe();
    return {
      ok: false,
      message:
        error instanceof Error ? error.message : "Could not save the device.",
    };
  }
  return { ok: true };
}

export async function turnOff() {
  const subscription = await currentSubscription();
  if (!subscription) return;
  const id = await subscriptionId(subscription.endpoint);
  const path = subscriptionPath(id);
  for (const item of getOutbox()) if (item.path === path) dismissItem(item.id);
  await subscription.unsubscribe();
  deleteDoc(doc(db, path)).catch(() => undefined);
}

export async function sendTest(): Promise<TestAnswer> {
  const token = await dataAuth.currentUser?.getIdToken().catch(() => null);
  if (!token) return describeTestResponse(401, null);
  try {
    const response = await fetch(`${pushWorkerOrigin}/push/test`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(15_000),
    });
    const body: unknown = await response.json().catch(() => null);
    return describeTestResponse(response.status, body);
  } catch {
    return {
      ok: false,
      text: "Could not reach the server. Check the connection and try again.",
    };
  }
}
