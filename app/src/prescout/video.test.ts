import { describe, expect, it } from "vitest";
import { openableUrl, youtubeEmbedUrl, youtubeVideoId } from "./video";

const id = "abcdefghijk";

describe("youtubeVideoId", () => {
  it.each([
    `https://www.youtube.com/watch?v=${id}`,
    `https://m.youtube.com/watch?v=${id}&t=5`,
    `https://youtu.be/${id}`,
    `https://www.youtube.com/embed/${id}`,
    `https://www.youtube.com/shorts/${id}`,
    `https://www.youtube.com/live/${id}`,
    `https://www.youtube-nocookie.com/embed/${id}`,
  ])("reads %s", (url) => {
    expect(youtubeVideoId(url)).toBe(id);
  });

  it.each([
    "",
    "not a url",
    "https://example.com/watch?v=abcdefghijk",
    "https://www.youtube.com/watch?v=short",
    "https://www.youtube.com/watch",
    "ftp://youtu.be/abcdefghijk",
    "https://evil.com/?u=youtube.com",
  ])("rejects %j", (url) => {
    expect(youtubeVideoId(url)).toBeNull();
  });
});

describe("youtubeEmbedUrl", () => {
  const base = `https://www.youtube-nocookie.com/embed/${id}`;
  it("carries the start offset", () => {
    expect(youtubeEmbedUrl(`https://youtu.be/${id}?t=90`)).toBe(
      `${base}?start=90`,
    );
    expect(youtubeEmbedUrl(`https://youtu.be/${id}?t=90s`)).toBe(
      `${base}?start=90`,
    );
    expect(youtubeEmbedUrl(`https://youtu.be/${id}?t=1m30s`)).toBe(
      `${base}?start=90`,
    );
    expect(youtubeEmbedUrl(`https://youtu.be/${id}?start=7`)).toBe(
      `${base}?start=7`,
    );
  });
  it("drops a missing or zero offset", () => {
    expect(youtubeEmbedUrl(`https://youtu.be/${id}`)).toBe(base);
    expect(youtubeEmbedUrl(`https://youtu.be/${id}?t=0`)).toBe(base);
    expect(youtubeEmbedUrl(`https://youtu.be/${id}?t=soon`)).toBe(base);
  });
  it("is null for other hosts", () => {
    expect(youtubeEmbedUrl("https://vimeo.com/1")).toBeNull();
  });
});

describe("openableUrl", () => {
  it("allows https only", () => {
    expect(openableUrl("https://example.com/a")).toBe("https://example.com/a");
    expect(openableUrl("http://example.com/a")).toBeNull();
    expect(openableUrl("javascript:alert(1)")).toBeNull();
  });
});
