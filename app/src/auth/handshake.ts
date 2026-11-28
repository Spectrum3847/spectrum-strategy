export type HandshakeErrorKind =
  | "not-approved"
  | "app-not-registered"
  | "popup-closed"
  | "no-app-key"
  | "bad-token"
  | "unreachable"
  | "unknown";

export class HandshakeError extends Error {
  readonly kind: HandshakeErrorKind;

  constructor(kind: HandshakeErrorKind, message: string) {
    super(message);
    this.name = "HandshakeError";
    this.kind = kind;
  }
}

export interface CentralHandshake {
  customToken: string;
}

export interface HandshakeDeps {
  appKey: string;
  signInWithGoogle(): Promise<void>;
  getCustomToken(targetApp: string): Promise<CentralHandshake>;
  signInWithCustomToken(token: string): Promise<void>;
  signOutCentral(): Promise<void>;
}

function codeOf(error: unknown): string {
  const code = (error as { code?: unknown } | null)?.code;
  return typeof code === "string" ? code.toLowerCase() : "";
}

export function classifyHandshakeError(error: unknown): HandshakeError {
  if (error instanceof HandshakeError) return error;
  const code = codeOf(error).replace(/^functions\//, "");
  switch (code) {
    case "permission-denied":
      return new HandshakeError(
        "not-approved",
        "This account is not approved for Spectrum Strategy. Ask a team admin.",
      );
    case "not-found":
      return new HandshakeError(
        "app-not-registered",
        "This app is not registered with the Spectrum platform yet.",
      );
    case "deadline-exceeded":
    case "unavailable":
    case "auth/network-request-failed":
      return new HandshakeError(
        "unreachable",
        "Could not reach the Spectrum sign-in service. Check the connection and try again.",
      );
    case "auth/invalid-custom-token":
    case "auth/custom-token-mismatch":
    case "auth/expired-custom-token":
      return new HandshakeError(
        "bad-token",
        "Sign-in did not finish in time. Try signing in again.",
      );
    case "auth/popup-closed-by-user":
    case "auth/cancelled-popup-request":
      return new HandshakeError("popup-closed", "Sign-in was cancelled.");
    default: {
      const detail = error instanceof Error ? error.message : String(error);
      return new HandshakeError("unknown", `Sign-in failed: ${detail}`);
    }
  }
}

export async function signInThroughCentral(deps: HandshakeDeps): Promise<void> {
  if (!deps.appKey) {
    throw new HandshakeError(
      "no-app-key",
      "This build has no app key, so it cannot sign in.",
    );
  }
  try {
    await deps.signInWithGoogle();
    const { customToken } = await deps.getCustomToken(deps.appKey);
    await deps.signInWithCustomToken(customToken);
  } catch (error) {
    await deps.signOutCentral().catch(() => undefined);
    throw classifyHandshakeError(error);
  }
}
