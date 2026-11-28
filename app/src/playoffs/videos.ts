import { readCache, writeCache } from "../data/cache";
import { parseMatchKey } from "../data/matchKey";
import { createStore, type Store, storeFor, useStore } from "../data/store";
import { teamKey } from "../data/tbaKey";
import { tbaGet } from "../scout/tba";

export type Videos = Record<string, string>;

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);

export function parseVideos(raw: unknown): Videos {
  const out: Videos = {};
  if (!Array.isArray(raw)) return out;
  for (const match of raw) {
    if (!isRecord(match) || typeof match.key !== "string") continue;
    if (parseMatchKey(match.key)?.level !== "qm") continue;
    const list = Array.isArray(match.videos) ? match.videos : [];
    for (const video of list) {
      if (
        isRecord(video) &&
        video.type === "youtube" &&
        typeof video.key === "string" &&
        /^[\w-]{6,20}$/.test(video.key)
      ) {
        out[match.key] = `https://www.youtube.com/watch?v=${video.key}`;
        break;
      }
    }
  }
  return out;
}

export interface QualVideos {
  status: "none" | "loading" | "ready" | "failed";
  videos: Videos;
}

const idle: QualVideos = { status: "none", videos: {} };
const refreshMs = 10 * 60_000;

function videoStore(eventKey: string): Store<QualVideos> {
  const cacheKey = `ss.playoff.videos.${eventKey}`;
  const cached = readCache<Videos>(cacheKey);
  const initial: QualVideos = cached
    ? { status: "ready", videos: cached }
    : idle;
  return createStore(initial, (set, get) => {
    let live = true;
    let running = false;
    const refresh = async () => {
      if (running) return;
      running = true;
      if (get().status !== "ready") set({ ...get(), status: "loading" });
      try {
        const apiKey = await teamKey();
        if (!apiKey) throw new Error("No TBA key available");
        const videos = parseVideos(
          await tbaGet(
            `/event/${encodeURIComponent(eventKey)}/matches`,
            apiKey,
          ),
        );
        writeCache(cacheKey, videos);
        if (live) set({ status: "ready", videos });
      } catch {
        if (live) {
          set({
            ...get(),
            status: get().status === "ready" ? "ready" : "failed",
          });
        }
      } finally {
        running = false;
      }
    };
    void refresh();
    const again = () => void refresh();
    window.addEventListener("online", again);
    const timer = setInterval(again, refreshMs);
    return () => {
      live = false;
      window.removeEventListener("online", again);
      clearInterval(timer);
    };
  });
}

export function useQualVideos(eventKey: string, enabled: boolean): QualVideos {
  const store =
    eventKey === "" || !enabled
      ? null
      : storeFor(`playoff-videos:${eventKey}`, () => videoStore(eventKey));
  return useStore(store, idle);
}
