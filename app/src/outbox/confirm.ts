export type OutboxStatus = "on-device" | "sending" | "in-database" | "refused";

export interface DocObservation {
  exists: boolean;
  hasPendingWrites: boolean;
  fromCache: boolean;
  online: boolean;
  matches?: boolean;
}

export function confirm(
  current: OutboxStatus,
  seen: DocObservation,
  snapshotConfirms = true,
): OutboxStatus {
  if (current === "in-database" || current === "refused") return current;
  if (
    snapshotConfirms &&
    seen.exists &&
    seen.matches !== false &&
    !seen.hasPendingWrites &&
    !seen.fromCache
  ) {
    return "in-database";
  }
  if (seen.exists && seen.hasPendingWrites) {
    return seen.online ? "sending" : "on-device";
  }
  return current;
}

export function isLostWrite(seen: DocObservation): boolean {
  return !seen.exists && !seen.hasPendingWrites && !seen.fromCache;
}

export function confirmDelete(
  current: OutboxStatus,
  seen: DocObservation,
): OutboxStatus {
  if (current === "in-database" || current === "refused") return current;
  if (!seen.exists && !seen.hasPendingWrites && !seen.fromCache) {
    return "in-database";
  }
  if (!seen.exists && seen.hasPendingWrites) {
    return seen.online ? "sending" : "on-device";
  }
  return current;
}

export function isLostDelete(seen: DocObservation): boolean {
  return seen.exists && !seen.hasPendingWrites && !seen.fromCache;
}

const refusalCodes = new Set([
  "permission-denied",
  "invalid-argument",
  "failed-precondition",
]);

export function isRefusal(code: string | undefined): boolean {
  return (
    code !== undefined && refusalCodes.has(code.replace(/^firestore\//, ""))
  );
}

export type ResendDecision = "none" | "wait-for-sign-in" | "resend";

export function resendDecision(
  status: OutboxStatus,
  signedIn: boolean,
): ResendDecision {
  if (status === "in-database" || status === "refused") return "none";
  return signedIn ? "resend" : "wait-for-sign-in";
}

export function shouldSend(queuedHere: boolean, online: boolean): boolean {
  return online && !queuedHere;
}

export function sameDocument(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (Array.isArray(a) || Array.isArray(b)) {
    return (
      Array.isArray(a) &&
      Array.isArray(b) &&
      a.length === b.length &&
      a.every((v, i) => sameDocument(v, b[i]))
    );
  }
  if (a && b && typeof a === "object" && typeof b === "object") {
    const ka = Object.keys(a as object);
    const kb = Object.keys(b as object);
    return (
      ka.length === kb.length &&
      ka.every((k) =>
        sameDocument(
          (a as Record<string, unknown>)[k],
          (b as Record<string, unknown>)[k],
        ),
      )
    );
  }
  return false;
}
