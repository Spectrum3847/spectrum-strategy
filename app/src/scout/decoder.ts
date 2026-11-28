import wasmUrl from "zxing-wasm/reader/zxing_reader.wasm?url";

let reader: Promise<typeof import("zxing-wasm/reader")> | undefined;

function load() {
  reader ??= import("zxing-wasm/reader").then((m) => {
    m.prepareZXingModule({
      overrides: {
        locateFile: (path: string, prefix: string) =>
          path.endsWith(".wasm") ? wasmUrl : prefix + path,
      },
    });
    return m;
  });
  return reader;
}

export async function decodeFrame(frame: ImageData): Promise<string | null> {
  const { readBarcodes } = await load();
  const [hit] = await readBarcodes(frame, {
    formats: ["QRCode"],
    maxNumberOfSymbols: 1,
    tryHarder: true,
  });
  return hit?.isValid ? new TextDecoder().decode(hit.bytes) : null;
}
