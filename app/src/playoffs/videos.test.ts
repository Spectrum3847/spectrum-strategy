import { describe, expect, it } from "vitest";
import { parseVideos } from "./videos";

describe("parseVideos", () => {
  it("keeps the YouTube link of each qualification match", () => {
    const out = parseVideos([
      {
        key: "2027test_qm1",
        videos: [
          { type: "tba", key: "x" },
          { type: "youtube", key: "abc123XYZ_-" },
        ],
      },
      { key: "2027test_qm2", videos: [] },
      { key: "2027test_qm3" },
      {
        key: "2027test_sf1m1",
        videos: [{ type: "youtube", key: "abc123XYZ_-" }],
      },
      { key: "2027test_qm4", videos: [{ type: "youtube", key: "bad key!" }] },
    ]);
    expect(out).toEqual({
      "2027test_qm1": "https://www.youtube.com/watch?v=abc123XYZ_-",
    });
  });

  it("reads anything else as no videos", () => {
    expect(parseVideos(null)).toEqual({});
    expect(parseVideos({})).toEqual({});
  });
});
