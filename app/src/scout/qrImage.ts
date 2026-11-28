import { encode } from "uqr";

export const qrMaxBytes = 2331;

export type QrMatrix =
  | { ok: true; size: number; modules: boolean[][] }
  | { ok: false; bytes: number };

export function qrMatrix(payload: string): QrMatrix {
  try {
    const { data, size } = encode(payload, {
      ecc: "M",
      boostEcc: false,
      border: 0,
    });
    return { ok: true, size, modules: data };
  } catch (error) {
    if (error instanceof RangeError) {
      return { ok: false, bytes: new TextEncoder().encode(payload).length };
    }
    throw error;
  }
}

export function qrPath(modules: boolean[][], quiet: number): string {
  const parts: string[] = [];
  modules.forEach((row, y) => {
    let x = 0;
    while (x < row.length) {
      if (!row[x]) {
        x++;
        continue;
      }
      const start = x;
      while (x < row.length && row[x]) x++;
      parts.push(`M${start + quiet} ${y + quiet}h${x - start}v1h${start - x}z`);
    }
  });
  return parts.join("");
}
