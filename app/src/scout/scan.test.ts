import { describe, expect, it } from "vitest";
import { parseConfig } from "./config";
import { decodeQrScout, encodeQrScout } from "./qr";
import {
  entryValues,
  qrConfig,
  referencePayload,
  referenceScanId,
  referenceSignature,
  schedule,
} from "./qr.fixture";
import {
  alreadyKnown,
  contentSignature,
  scanIdFor,
  scanToEntry,
  stableHash,
} from "./scan";

const ctx = {
  config: qrConfig,
  schedule,
  eventKey: "2027test",
  author: { uid: "uid-1", displayName: "Sam Scout" },
  now: new Date("2027-03-05T18:04:05.123Z"),
};

describe("stableHash", () => {
  it("is FNV-1a over 32 bits", () => {
    expect(stableHash("")).toBe("811c9dc5");
    expect(stableHash("a")).toBe("e40c292c");
    expect(stableHash("foobar")).toBe("bf9cf968");
  });
});

describe("reference payload", () => {
  it("builds the reference signature for the scanned entry", () => {
    const decoded = decodeQrScout(qrConfig, referencePayload);
    if (!decoded) throw new Error("payload should decode");
    expect(
      contentSignature("2027test_qm12", 1234, decoded.values, decoded.doubles),
    ).toBe(referenceSignature);
  });

  it("derives the id Dart derives", () => {
    expect(scanIdFor(referenceSignature)).toBe(referenceScanId);
    const scan = scanToEntry(referencePayload, ctx);
    expect(scan.ok && scan.id).toBe(referenceScanId);
  });

  it("encoding the entry gives back the same payload", () => {
    expect(encodeQrScout(qrConfig, entryValues)).toBe(referencePayload);
  });

  it("prints a whole-number range as a Dart double", () => {
    const decoded = decodeQrScout(
      qrConfig,
      referencePayload.replace("3.5", "3"),
    );
    if (!decoded) throw new Error("payload should decode");
    const sig = contentSignature(null, 1234, decoded.values, decoded.doubles);
    expect(sig).toContain('"level":3.0,');
    expect(sig).toContain('"tbaMatchKey":""');
    expect(sig).toContain('"fuel":7,');
  });
});

describe("scanToEntry", () => {
  it("gives one id to one payload and another to changed content", () => {
    const a = scanToEntry(referencePayload, ctx);
    const b = scanToEntry(referencePayload, { ...ctx, now: new Date() });
    const c = scanToEntry(referencePayload.replace("\t7\t", "\t8\t"), ctx);
    expect(a.ok && b.ok && c.ok).toBe(true);
    if (a.ok && b.ok && c.ok) {
      expect(a.id).toBe(b.id);
      expect(a.id).not.toBe(c.id);
    }
  });

  it("writes a document the rules accept", () => {
    const scan = scanToEntry(referencePayload, ctx);
    if (!scan.ok) throw new Error(scan.error);
    expect(scan.doc).toMatchObject({
      id: referenceScanId,
      matchId: "2027test_qm12",
      tbaMatchKey: "2027test_qm12",
      teamNumber: 1234,
      alliance: "Red",
      authorUid: "uid-1",
      authorDisplayName: "Sam Scout",
      fieldValues: { matchNumber: 12, pTnumber: 1234, level: 3.5, fuel: 7 },
    });
    expect(scan.entry).toMatchObject({
      id: referenceScanId,
      matchNumber: "12",
      team: 1234,
      station: "R2",
      qr: referencePayload,
    });
  });

  it("keeps a typed match when the schedule does not have it", () => {
    const scan = scanToEntry(referencePayload, { ...ctx, schedule: [] });
    if (!scan.ok) throw new Error(scan.error);
    expect(scan.doc.matchId).toBe("2027test_typed_12");
    expect(scan.doc).not.toHaveProperty("tbaMatchKey");
  });

  it("refuses data it cannot place", () => {
    expect(scanToEntry("not scout data", ctx)).toMatchObject({ ok: false });
    const noMatchField = parseConfig({
      sections: [
        {
          name: "x",
          fields: [
            { code: "robot", type: "select" },
            { code: "pTnumber", type: "number" },
          ],
        },
      ],
    });
    expect(
      scanToEntry("R2\t1234", { ...ctx, config: noMatchField }),
    ).toMatchObject({
      ok: false,
      error: expect.stringContaining("match number"),
    });
    const noTeam = referencePayload.replace("\t1234\t", "\t0\t");
    expect(scanToEntry(noTeam, ctx)).toMatchObject({
      ok: false,
      error: expect.stringContaining("team number"),
    });
  });
});

describe("alreadyKnown", () => {
  const scan = scanToEntry(referencePayload, ctx);
  if (!scan.ok) throw new Error(scan.error);

  it("is false for a new entry", () => {
    expect(alreadyKnown(qrConfig, scan, referencePayload, [], [])).toBe(false);
  });

  it("matches the same scan id here or in the database", () => {
    expect(
      alreadyKnown(qrConfig, scan, referencePayload, [], [scan.entry]),
    ).toBe(true);
    expect(
      alreadyKnown(
        qrConfig,
        scan,
        referencePayload,
        [{ id: scan.id, tbaMatchKey: null, fieldValues: {} }],
        [],
      ),
    ).toBe(true);
  });

  it("matches an original synced entry whose payload is identical", () => {
    const original = {
      id: "uuid-1",
      tbaMatchKey: "2027test_qm12",
      fieldValues: entryValues,
    };
    expect(alreadyKnown(qrConfig, scan, referencePayload, [original], [])).toBe(
      true,
    );
    const other = { ...original, fieldValues: { ...entryValues, fuel: 9 } };
    expect(alreadyKnown(qrConfig, scan, referencePayload, [other], [])).toBe(
      false,
    );
  });
});
