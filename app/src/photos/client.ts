import { photoUrl, uploadUrl } from "./keys";
import type { Outcome } from "./state";

export interface ClientDeps {
  origin(): Promise<string | null>;
  token(): Promise<string | null>;
  online(): boolean;
  fetch: typeof fetch;
}

type Unavailable = Extract<Outcome, { type: "unavailable" }>;

export type DownloadResult =
  | { type: "ok"; blob: Blob }
  | Unavailable
  | { type: "failed" };

export function createClient(deps: ClientDeps) {
  async function ready(): Promise<
    { origin: string; token: string } | Unavailable
  > {
    if (!deps.online()) return { type: "unavailable", reason: "offline" };
    const origin = await deps.origin();
    if (origin === null) return { type: "unavailable", reason: "unconfigured" };
    const token = await deps.token();
    if (token === null) return { type: "unavailable", reason: "signed-out" };
    return { origin, token };
  }

  const send = (url: string, init: RequestInit, token: string) =>
    deps.fetch(url, {
      ...init,
      redirect: "error",
      headers: { ...init.headers, Authorization: `Bearer ${token}` },
    });

  async function upload(blob: Blob): Promise<Outcome> {
    const got = await ready();
    if ("type" in got) return got;
    try {
      const response = await send(
        uploadUrl(got.origin),
        {
          method: "POST",
          headers: { "Content-Type": blob.type || "image/jpeg" },
          body: blob,
        },
        got.token,
      );
      if (response.status !== 201) {
        return { type: "response", status: response.status };
      }
      const body: unknown = await response.json();
      const key =
        body && typeof body === "object" && "key" in body ? body.key : null;
      return typeof key === "string" && key !== ""
        ? { type: "response", status: 201, key }
        : { type: "response", status: 502 };
    } catch {
      return { type: "network" };
    }
  }

  async function download(key: string): Promise<DownloadResult> {
    const got = await ready();
    if ("type" in got) return got;
    try {
      const response = await send(
        photoUrl(got.origin, key),
        { method: "GET" },
        got.token,
      );
      if (response.status === 401 || response.status === 403) {
        return { type: "unavailable", reason: "signed-out" };
      }
      if (response.status !== 200) return { type: "failed" };
      return { type: "ok", blob: await response.blob() };
    } catch {
      return { type: "failed" };
    }
  }

  async function remove(key: string): Promise<boolean> {
    const got = await ready();
    if ("type" in got) return false;
    try {
      const response = await send(
        photoUrl(got.origin, key),
        { method: "DELETE" },
        got.token,
      );
      return response.status === 204 || response.status === 404;
    } catch {
      return false;
    }
  }

  return { upload, download, remove };
}

export type PhotoClient = ReturnType<typeof createClient>;
