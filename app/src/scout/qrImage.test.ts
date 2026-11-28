import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";
import { referencePayload } from "./qr.fixture";
import { qrMatrix, qrMaxBytes, qrPath } from "./qrImage";

describe("qrMatrix", () => {
  it("draws a payload that fits", () => {
    const qr = qrMatrix(referencePayload);
    expect(qr.ok && qr.size).toBeGreaterThanOrEqual(21);
    expect(qr.ok && qr.modules.length).toBe(qr.ok ? qr.size : 0);
  });

  it("reports a payload that is too long instead of drawing it", () => {
    const qr = qrMatrix("x".repeat(qrMaxBytes + 1));
    expect(qr).toEqual({ ok: false, bytes: qrMaxBytes + 1 });
  });

  it("still draws the longest payload that fits", () => {
    expect(qrMatrix("x".repeat(qrMaxBytes)).ok).toBe(true);
  });

  it("counts bytes, not characters, for the limit", () => {
    const qr = qrMatrix("é".repeat(1200));
    expect(qr).toEqual({ ok: false, bytes: 2400 });
  });
});

describe("qrPath", () => {
  it("merges a run of dark modules and offsets by the quiet zone", () => {
    expect(qrPath([[true, true, false, true]], 4)).toBe(
      "M4 4h2v1h-2zM7 4h1v1h-1z",
    );
  });
});

describe("drawn code read back by the scanner decoder", () => {
  it("returns the payload unchanged", async () => {
    const qr = qrMatrix(referencePayload);
    if (!qr.ok) throw new Error("should fit");
    const scale = 6;
    const quiet = 4;
    const side = (qr.size + quiet * 2) * scale;
    const data = new Uint8ClampedArray(side * side * 4).fill(255);
    qr.modules.forEach((row, y) => {
      row.forEach((dark, x) => {
        if (!dark) return;
        for (let dy = 0; dy < scale; dy++) {
          for (let dx = 0; dx < scale; dx++) {
            const px =
              ((y + quiet) * scale + dy) * side + (x + quiet) * scale + dx;
            data.fill(0, px * 4, px * 4 + 3);
          }
        }
      });
    });
    const require = createRequire(import.meta.url);
    const wasm = readFileSync(
      require.resolve("zxing-wasm/reader/zxing_reader.wasm"),
    );
    const { prepareZXingModule, readBarcodes } = await import(
      "zxing-wasm/reader"
    );
    prepareZXingModule({
      overrides: { wasmBinary: wasm.buffer as ArrayBuffer },
    });
    const [hit] = await readBarcodes(
      { data, width: side, height: side, colorSpace: "srgb" } as ImageData,
      { formats: ["QRCode"] },
    );
    expect(hit?.isValid).toBe(true);
    expect(new TextDecoder().decode(hit?.bytes)).toBe(referencePayload);
  }, 60_000);
});
