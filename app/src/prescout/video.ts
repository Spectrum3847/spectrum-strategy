const idPattern = /^[A-Za-z0-9_-]{11}$/;
const validId = (s: string | undefined) =>
  s !== undefined && idPattern.test(s) ? s : null;

function parse(url: string): URL | null {
  try {
    const u = new URL(url.trim());
    return u.protocol === "https:" || u.protocol === "http:" ? u : null;
  } catch {
    return null;
  }
}

export function youtubeVideoId(url: string): string | null {
  const u = parse(url);
  if (!u) return null;
  const host = u.hostname.toLowerCase().replace(/^www\./, "");
  const parts = u.pathname.split("/").filter(Boolean);
  if (host === "youtu.be") return validId(parts[0]);
  if (
    host !== "youtube.com" &&
    host !== "m.youtube.com" &&
    host !== "youtube-nocookie.com"
  ) {
    return null;
  }
  const first = parts[0];
  if (
    first === "embed" ||
    first === "shorts" ||
    first === "live" ||
    first === "v"
  ) {
    return validId(parts[1]);
  }
  return validId(u.searchParams.get("v") ?? undefined);
}

function startSeconds(u: URL | null): number | null {
  const raw = (u?.searchParams.get("t") ?? u?.searchParams.get("start") ?? "")
    .trim()
    .toLowerCase();
  if (raw === "") return null;
  const plain = /^\d+s?$/.exec(raw);
  if (plain) {
    const n = Number.parseInt(raw, 10);
    return n > 0 ? n : null;
  }
  const m = /^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/.exec(raw);
  if (!m) return null;
  const total =
    Number(m[1] ?? 0) * 3600 + Number(m[2] ?? 0) * 60 + Number(m[3] ?? 0);
  return total > 0 ? total : null;
}

export function youtubeEmbedUrl(url: string): string | null {
  const id = youtubeVideoId(url);
  if (id === null) return null;
  const start = startSeconds(parse(url));
  return `https://www.youtube-nocookie.com/embed/${id}${start === null ? "" : `?start=${start}`}`;
}

export function openableUrl(url: string): string | null {
  const u = parse(url);
  return u?.protocol === "https:" ? u.href : null;
}
