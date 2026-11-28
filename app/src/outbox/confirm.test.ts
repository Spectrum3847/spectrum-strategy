import { describe, expect, it } from "vitest";
import {
  confirm,
  confirmDelete,
  type DocObservation,
  isLostDelete,
  isLostWrite,
  isRefusal,
  resendDecision,
  sameDocument,
  shouldSend,
} from "./confirm";

const base: DocObservation = {
  exists: true,
  hasPendingWrites: false,
  fromCache: false,
  online: true,
};

describe("confirm", () => {
  it("shows a pending write as sending while online", () => {
    const seen = { ...base, hasPendingWrites: true, fromCache: true };
    expect(confirm("on-device", seen)).toBe("sending");
  });

  it("keeps a pending write on the device while offline", () => {
    const seen = {
      ...base,
      hasPendingWrites: true,
      fromCache: true,
      online: false,
    };
    expect(confirm("on-device", seen)).toBe("on-device");
  });

  it("does not confirm from a cache-only snapshot", () => {
    const seen = { ...base, fromCache: true };
    expect(confirm("on-device", seen)).toBe("on-device");
    expect(confirm("sending", seen)).toBe("sending");
  });

  it("confirms a server snapshot with no pending write", () => {
    expect(confirm("on-device", base)).toBe("in-database");
  });

  it("does not confirm a merge from a plain server snapshot", () => {
    expect(confirm("on-device", base, false)).toBe("on-device");
    expect(confirm("sending", base, false)).toBe("sending");
  });

  it("still shows a pending merge as sending or on the device", () => {
    const pending = { ...base, hasPendingWrites: true, fromCache: true };
    expect(confirm("on-device", pending, false)).toBe("sending");
    expect(confirm("on-device", { ...pending, online: false }, false)).toBe(
      "on-device",
    );
  });

  it("confirms when the ack follows a pending snapshot", () => {
    const pending = { ...base, hasPendingWrites: true, fromCache: true };
    const sending = confirm("on-device", pending);
    expect(confirm(sending, base)).toBe("in-database");
  });

  it("does not confirm a server snapshot that still has a pending write", () => {
    const seen = { ...base, hasPendingWrites: true };
    expect(confirm("on-device", seen)).toBe("sending");
  });

  it("does not refuse or confirm when the server has no doc", () => {
    const seen = { ...base, exists: false };
    expect(confirm("sending", seen)).toBe("sending");
  });

  it("never leaves in-database or refused", () => {
    expect(confirm("in-database", { ...base, exists: false })).toBe(
      "in-database",
    );
    expect(confirm("refused", base)).toBe("refused");
  });
});

describe("isLostWrite", () => {
  it("flags a server snapshot with no doc and nothing pending", () => {
    expect(isLostWrite({ ...base, exists: false })).toBe(true);
  });

  it("does not flag a cache snapshot, a pending write or an existing doc", () => {
    expect(isLostWrite({ ...base, exists: false, fromCache: true })).toBe(
      false,
    );
    expect(
      isLostWrite({ ...base, exists: false, hasPendingWrites: true }),
    ).toBe(false);
    expect(isLostWrite(base)).toBe(false);
  });
});

describe("isRefusal", () => {
  it("refuses only on permission and validation errors", () => {
    expect(isRefusal("permission-denied")).toBe(true);
    expect(isRefusal("firestore/invalid-argument")).toBe(true);
    expect(isRefusal("failed-precondition")).toBe(true);
    expect(isRefusal("unavailable")).toBe(false);
    expect(isRefusal(undefined)).toBe(false);
  });
});

describe("resendDecision", () => {
  it("resends an unconfirmed item when signed in, including a lost write", () => {
    expect(resendDecision("on-device", true)).toBe("resend");
    expect(resendDecision("sending", true)).toBe("resend");
  });

  it("waits for sign-in when signed out", () => {
    expect(resendDecision("on-device", false)).toBe("wait-for-sign-in");
    expect(resendDecision("sending", false)).toBe("wait-for-sign-in");
  });

  it("leaves confirmed and refused items alone", () => {
    expect(resendDecision("in-database", true)).toBe("none");
    expect(resendDecision("refused", true)).toBe("none");
  });
});

describe("shouldSend", () => {
  it("sends once while online and not already queued here", () => {
    expect(shouldSend(false, true)).toBe(true);
  });
  it("does not stack a second copy of a queued write", () => {
    expect(shouldSend(true, true)).toBe(false);
  });
  it("waits while offline", () => {
    expect(shouldSend(false, false)).toBe(false);
  });
});

describe("whole-document confirmation", () => {
  const server = {
    exists: true,
    hasPendingWrites: false,
    fromCache: false,
    online: true,
  };

  it("confirms only when the server copy is what this item wrote", () => {
    expect(confirm("sending", { ...server, matches: true })).toBe(
      "in-database",
    );
    expect(confirm("sending", { ...server, matches: false })).toBe("sending");
  });

  it("compares documents regardless of key order", () => {
    expect(
      sameDocument({ a: 1, b: { c: [1, 2] } }, { b: { c: [1, 2] }, a: 1 }),
    ).toBe(true);
    expect(sameDocument({ a: 1 }, { a: 1, b: 2 })).toBe(false);
    expect(sameDocument({ a: [1, 2] }, { a: [2, 1] })).toBe(false);
  });
});

describe("delete confirmation", () => {
  const gone = { ...base, exists: false };

  it("confirms a server snapshot with no document and no pending write", () => {
    expect(confirmDelete("on-device", gone)).toBe("in-database");
    expect(confirmDelete("sending", gone)).toBe("in-database");
  });

  it("does not confirm from a cache-only snapshot", () => {
    expect(confirmDelete("on-device", { ...gone, fromCache: true })).toBe(
      "on-device",
    );
  });

  it("does not confirm while the document still exists", () => {
    expect(confirmDelete("sending", base)).toBe("sending");
  });

  it("shows a pending delete as sending online and on the device offline", () => {
    const pending = { ...gone, hasPendingWrites: true, fromCache: true };
    expect(confirmDelete("on-device", pending)).toBe("sending");
    expect(confirmDelete("on-device", { ...pending, online: false })).toBe(
      "on-device",
    );
  });

  it("keeps a finished or refused delete as it is", () => {
    expect(confirmDelete("in-database", base)).toBe("in-database");
    expect(confirmDelete("refused", gone)).toBe("refused");
  });

  it("sends a delete again when the server still has the document", () => {
    expect(isLostDelete(base)).toBe(true);
    expect(isLostDelete({ ...base, hasPendingWrites: true })).toBe(false);
    expect(isLostDelete({ ...base, fromCache: true })).toBe(false);
    expect(isLostDelete(gone)).toBe(false);
  });
});
