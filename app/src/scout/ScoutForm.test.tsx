// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { parseConfig } from "./config";
import { parseShifts, type StandIn } from "./credit";
import { draftStore, type SavedEntry } from "./local";
import { ScoutForm, type ScoutFormProps } from "./ScoutForm";
import type { ScheduledMatch } from "./schedule";

const config = parseConfig({
  title: "T",
  revision: 1,
  sections: [
    {
      name: "Pre",
      fields: [
        {
          code: "scouter",
          title: "scouter",
          type: "text",
          required: true,
          formResetBehavior: "preserve",
        },
        {
          code: "matchNumber",
          title: "matchNumber",
          type: "TBA-match-number",
          required: true,
          defaultValue: 1,
        },
        {
          code: "robot",
          title: "robot",
          type: "select",
          required: true,
          choices: { R1: "R1", R2: "R2", B1: "B1" },
          defaultValue: "R1",
          formResetBehavior: "preserve",
        },
        {
          code: "pTnumber",
          title: "pTnumber",
          type: "number",
          required: true,
          defaultValue: 0,
        },
      ],
    },
    {
      name: "Auto",
      fields: [
        { code: "fuel", title: "fuel", type: "counter", buttons: [1, 5] },
        {
          code: "kind",
          title: "kind",
          type: "select",
          choices: { a: "A", other: "Other" },
          defaultValue: "a",
        },
        {
          code: "detail",
          title: "detail",
          type: "text",
          visibleWhenCode: "kind",
          visibleWhenValue: "other",
        },
      ],
    },
  ],
});

const schedule: ScheduledMatch[] = [1, 2].map((n) => ({
  key: `2027test_qm${n}`,
  compLevel: "qm",
  matchNumber: n,
  red: [100 * n + 1, 100 * n + 2, 100 * n + 3],
  blue: [100 * n + 4, 100 * n + 5, 100 * n + 6],
}));

let persisted: { doc: Record<string, unknown>; entry: SavedEntry }[] = [];
let saved: SavedEntry[] = [];

function props(over: Partial<ScoutFormProps> = {}): ScoutFormProps {
  return {
    config,
    schedule,
    eventKey: "2027test",
    deviceStation: "R1",
    author: { uid: "uid-1", displayName: "Sam Scout" },
    online: true,
    saved,
    unsent: { pending: 0, refused: 0 },
    deliveryOf: () => ({ status: "sending" }),
    persist: async (doc, entry) => {
      persisted.push({ doc, entry });
    },
    onStation: () => undefined,
    ...over,
  };
}

beforeEach(() => {
  localStorage.clear();
  persisted = [];
  saved = [];
  window.scrollTo = vi.fn();
});
afterEach(cleanup);

const typeScouter = (name: string) =>
  fireEvent.change(screen.getByLabelText("scouter"), {
    target: { value: name },
  });

describe("steps and header", () => {
  it("pins match, station and team from the schedule", () => {
    render(<ScoutForm {...props()} />);
    expect(screen.getByText("Match 1")).toBeTruthy();
    expect(screen.getByText("Team 101")).toBeTruthy();
    const tag = screen.getByText("R1", { selector: ".tag" });
    expect(tag.getAttribute("data-alliance")).toBe("red");
  });

  it("shows one section per step, ending with a review", () => {
    render(<ScoutForm {...props()} />);
    expect(screen.getByRole("heading", { name: "Pre" })).toBeTruthy();
    expect(screen.queryByText("fuel")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(screen.getByRole("heading", { name: "Auto" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(screen.getByRole("heading", { name: "Review" })).toBeTruthy();
    expect(
      (screen.getByRole("button", { name: "Next" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
    fireEvent.click(screen.getByRole("button", { name: "Back" }));
    expect(screen.getByRole("heading", { name: "Auto" })).toBeTruthy();
  });

  it("keeps Save on screen in every step", () => {
    render(<ScoutForm {...props()} />);
    for (const step of ["Pre", "Auto", "Review"]) {
      fireEvent.click(screen.getByRole("button", { name: step }));
      const footer = screen.getByRole("contentinfo");
      expect(within(footer).getByRole("button", { name: "Save" })).toBeTruthy();
    }
  });

  it("shows one compact status line with online state and unsent count", () => {
    render(
      <ScoutForm
        {...props({ online: false, unsent: { pending: 2, refused: 1 } })}
      />,
    );
    const line = document.querySelector(".status-line");
    expect(line?.textContent).toBe("2027testOffline2 unsent1 refused");
    expect(screen.getByText("Offline")).toBeTruthy();
    expect(screen.getByText("2 unsent")).toBeTruthy();
    expect(screen.getByText("1 refused")).toBeTruthy();
  });

  it("reveals a field when its visibleWhen value is set", () => {
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Auto" }));
    expect(screen.queryByLabelText("detail")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Other" }));
    expect(screen.getByLabelText("detail")).toBeTruthy();
  });

  it("counts with the big buttons", () => {
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Auto" }));
    fireEvent.click(screen.getByRole("button", { name: "fuel plus 5" }));
    fireEvent.click(screen.getByRole("button", { name: "fuel plus 1" }));
    expect(screen.getByLabelText("fuel value").textContent).toBe("6");
    fireEvent.click(screen.getByRole("button", { name: "fuel minus 5" }));
    expect(screen.getByLabelText("fuel value").textContent).toBe("1");
    expect(
      (
        screen.getByRole("button", {
          name: "fuel minus 5",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
  });

  it("remembers the station when it changes", () => {
    const onStation = vi.fn();
    render(<ScoutForm {...props({ onStation })} />);
    fireEvent.click(screen.getByRole("button", { name: "B1" }));
    expect(onStation).toHaveBeenCalledWith("B1");
    expect(screen.getByText("Team 104")).toBeTruthy();
  });

  it("asks for the station once when none is stored", () => {
    render(<ScoutForm {...props({ deviceStation: null })} />);
    expect(screen.getByText(/Pick your station once/)).toBeTruthy();
  });
});

describe("save", () => {
  it("needs a sign-in", () => {
    render(
      <ScoutForm {...props({ author: { uid: null, displayName: null } })} />,
    );
    const button = screen.getByRole("button", {
      name: "Sign in to save",
    }) as HTMLButtonElement;
    expect(button.disabled).toBe(true);
  });

  it("sends required-but-empty answers to the review before saving", () => {
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(screen.getByRole("heading", { name: "Review" })).toBeTruthy();
    const alert = screen.getByRole("alert");
    expect(within(alert).getByRole("button", { name: "scouter" })).toBeTruthy();
    expect(persisted).toHaveLength(0);
  });

  it("saves anyway on a second press, with the empty answer kept", async () => {
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    fireEvent.click(await screen.findByRole("button", { name: "Save anyway" }));
    expect(await screen.findByText("Team 101 saved")).toBeTruthy();
    expect(persisted).toHaveLength(1);
  });

  it("jumps to the step of a required field from the review", () => {
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    fireEvent.click(screen.getByRole("button", { name: "scouter" }));
    expect(screen.getByRole("heading", { name: "Pre" })).toBeTruthy();
  });

  it("refuses an entry with no team", () => {
    render(<ScoutForm {...props({ schedule: [] })} />);
    typeScouter("Sam");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(screen.getByRole("alert").textContent).toContain(
      "Enter the team number",
    );
    expect(persisted).toHaveLength(0);
  });

  it("writes the entry document, confirms, and advances to the next match", async () => {
    const view = render(<ScoutForm {...props()} />);
    typeScouter("Sam");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(await screen.findByText("Team 101 saved")).toBeTruthy();
    expect(screen.getByText("Sending")).toBeTruthy();

    const { doc, entry } = persisted[0] ?? {};
    expect(doc).toMatchObject({
      matchId: "2027test_qm1",
      tbaMatchKey: "2027test_qm1",
      teamNumber: 101,
      alliance: "Red",
      authorUid: "uid-1",
      authorDisplayName: "Sam Scout",
      fieldValues: {
        scouter: "Sam",
        matchNumber: "1",
        robot: "R1",
        pTnumber: "101",
        fuel: 0,
      },
    });
    expect(entry).toMatchObject({ matchRef: "2027test_qm1", team: 101 });

    saved = entry ? [entry] : [];
    view.rerender(<ScoutForm {...props({ saved })} />);
    fireEvent.click(screen.getByRole("button", { name: "Next match" }));
    expect(screen.getByText("Match 2")).toBeTruthy();
    expect(screen.getByText("Team 201")).toBeTruthy();
    expect((screen.getByLabelText("scouter") as HTMLInputElement).value).toBe(
      "Sam",
    );
  });

  it("lists what this device saved for the match, keyed by match key", async () => {
    saved = [
      {
        id: "earlier",
        matchId: "2027test_qm1",
        matchRef: "2027test_qm1",
        matchNumber: "1",
        team: 102,
        tbaMatchKey: "2027test_qm1",
        station: "R2",
        createdAt: "2027-03-05T18:00:00.000Z",
        savedAt: "2027-03-05T18:00:00.000Z",
      },
      {
        id: "other-match",
        matchId: "2027test_qm2",
        matchRef: "2027test_qm2",
        matchNumber: "2",
        team: 202,
        tbaMatchKey: "2027test_qm2",
        station: "R2",
        createdAt: "2027-03-05T18:00:00.000Z",
        savedAt: "2027-03-05T18:00:00.000Z",
      },
    ];
    render(
      <ScoutForm
        {...props({
          deliveryOf: (id) =>
            id === "earlier" ? { status: "in-database" } : undefined,
        })}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Review" }));
    const list = screen.getByRole("heading", { name: "Saved this match" })
      .parentElement as HTMLElement;
    expect(within(list).getByText("Team 102 at R2")).toBeTruthy();
    expect(within(list).getByText("In the database")).toBeTruthy();
    expect(within(list).queryByText("Team 202 at R2")).toBeNull();
  });
});

describe("QR and other scouts", () => {
  const entry = (over: Partial<SavedEntry> = {}): SavedEntry => ({
    id: "earlier",
    matchId: "2027test_qm1",
    matchRef: "2027test_qm1",
    matchNumber: "1",
    team: 102,
    tbaMatchKey: "2027test_qm1",
    station: "R2",
    createdAt: "2027-03-05T18:00:00.000Z",
    savedAt: "2027-03-05T18:00:00.000Z",
    qr: "Sam\t1\tR2\t102",
    ...over,
  });

  it("shows the QR of a saved entry with match, station and team under it", () => {
    saved = [entry()];
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Review" }));
    fireEvent.click(
      screen.getByRole("button", { name: "Show QR for team 102" }),
    );
    const dialog = screen.getByRole("dialog");
    expect(
      within(dialog).getByRole("img").getAttribute("aria-label"),
    ).toContain("Match 1, R2, team 102");
    expect(dialog.textContent).toContain("Match 1");
    expect(dialog.textContent).toContain("R2");
    expect(dialog.textContent).toContain("Team 102");
    fireEvent.click(within(dialog).getByRole("button", { name: "Close" }));
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("offers the QR right after Save", async () => {
    render(<ScoutForm {...props()} />);
    typeScouter("Sam");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByText("Team 101 saved");
    fireEvent.click(screen.getByRole("button", { name: "Show QR" }));
    expect(screen.getByRole("dialog")).toBeTruthy();
    expect(persisted[0]?.entry.qr).toContain("Sam");
  });

  it("says plainly when a payload is too long for one code", () => {
    saved = [entry({ qr: "x".repeat(3000) })];
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Review" }));
    fireEvent.click(
      screen.getByRole("button", { name: "Show QR for team 102" }),
    );
    expect(
      within(screen.getByRole("dialog")).getByRole("alert").textContent,
    ).toContain("more than one QR code can hold");
    expect(screen.queryByRole("img")).toBeNull();
  });

  it("says so when an old entry no longer keeps its QR", () => {
    const { qr: _qr, ...old } = entry();
    saved = [old];
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Review" }));
    fireEvent.click(
      screen.getByRole("button", { name: "Show QR for team 102" }),
    );
    expect(
      within(screen.getByRole("dialog")).getByRole("alert").textContent,
    ).toContain("no longer kept");
  });

  it("prefills the next match from other scouts' entries", () => {
    const remote = [
      { id: "a", tbaMatchKey: "2027test_qm1", fieldValues: { robot: "B1" } },
      { id: "b", tbaMatchKey: "2027test_qm1", fieldValues: { robot: "B2" } },
    ];
    render(<ScoutForm {...props({ remote })} />);
    expect(screen.getByText("Match 1")).toBeTruthy();
    cleanup();
    localStorage.clear();
    const later = [
      { id: "a", tbaMatchKey: "2027test_qm1", fieldValues: { robot: "R1" } },
    ];
    render(<ScoutForm {...props({ remote: later })} />);
    expect(screen.getByText("Match 2")).toBeTruthy();
    expect(screen.getByText("Team 201")).toBeTruthy();
  });

  it("links to the scanner from the Scout tab", () => {
    const onScan = vi.fn();
    render(<ScoutForm {...props({ onScan })} />);
    fireEvent.click(screen.getByRole("button", { name: "Scan QR" }));
    expect(onScan).toHaveBeenCalled();
  });
});

const names = ["Ada", "Ben", "Cy", "Di", "Eli", "Fay"];
const stations = ["R1", "R2", "R3", "B1", "B2", "B3"];
const shifts = parseShifts({
  matchCount: 12,
  roster: names.map((name, i) => ({ uid: `u${i}`, name })),
  rotations: names.map((name, i) => ({
    uid: `u${i}`,
    name,
    shifts: [{ startMatch: 1, endMatch: 6, station: stations[i] }],
  })),
});

function stationProps(over: Partial<ScoutFormProps> = {}) {
  return props({ stationLocked: true, shifts, onStandIn: vi.fn(), ...over });
}

describe("station credit", () => {
  it("shows who the schedule puts on the locked station", () => {
    render(<ScoutForm {...stationProps({ deviceStation: "R2" })} />);
    expect(screen.getByText("Scouting as")).toBeTruthy();
    expect(screen.getByText("Ben")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Not me? Switch" })).toBeTruthy();
  });

  it("does not ask for the station when it is locked", () => {
    render(<ScoutForm {...stationProps()} />);
    expect(screen.queryByRole("button", { name: "B1" })).toBeNull();
    expect(screen.queryByText(/Pick your station/)).toBeNull();
    expect(screen.getByText("Team 101")).toBeTruthy();
  });

  it("shows no credit row without a lock or without a schedule", () => {
    const { unmount } = render(
      <ScoutForm {...props({ shifts, stationLocked: false })} />,
    );
    expect(screen.queryByText("Scouting as")).toBeNull();
    unmount();
    render(<ScoutForm {...props({ stationLocked: true, shifts: null })} />);
    expect(screen.queryByText("Scouting as")).toBeNull();
  });

  it("saves the entry with the credit and the account as author", async () => {
    render(<ScoutForm {...stationProps({ deviceStation: "R2" })} />);
    typeScouter("Sam");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByText("Team 102 saved");
    const doc = persisted[0]?.doc;
    expect(doc).toMatchObject({
      authorUid: "uid-1",
      scoutedByName: "Ben",
      scoutedByUid: "u1",
    });
    expect(persisted[0]?.entry.qr).not.toContain("Ben");
  });

  it("omits the credit fields with no lock", async () => {
    render(<ScoutForm {...props({ shifts })} />);
    typeScouter("Sam");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByText("Team 101 saved");
    expect("scoutedByName" in (persisted[0]?.doc ?? {})).toBe(false);
  });

  it("switches to a roster name and reports a stand-in for the block", () => {
    const onStandIn = vi.fn();
    render(<ScoutForm {...stationProps({ onStandIn })} />);
    fireEvent.click(screen.getByRole("button", { name: "Not me? Switch" }));
    const sheet = screen.getByRole("dialog");
    fireEvent.click(within(sheet).getByRole("button", { name: "Fay" }));
    expect(onStandIn).toHaveBeenCalledWith({
      eventKey: "2027test",
      station: "R1",
      name: "Fay",
      uid: "u5",
      fromMatch: 1,
      untilMatch: 6,
    });
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("switches to a typed name with no uid", () => {
    const onStandIn = vi.fn();
    render(<ScoutForm {...stationProps({ onStandIn })} />);
    fireEvent.click(screen.getByRole("button", { name: "Not me? Switch" }));
    fireEvent.change(screen.getByLabelText("Type a name"), {
      target: { value: " Zed " },
    });
    fireEvent.click(screen.getByRole("button", { name: "Use this name" }));
    expect(onStandIn.mock.calls[0]?.[0]).toMatchObject({
      name: "Zed",
      uid: "",
    });
  });

  it("credits an active stand-in and can go back to the schedule", async () => {
    const standIn: StandIn = {
      eventKey: "2027test",
      station: "R1",
      name: "Zed",
      uid: "",
      fromMatch: 1,
      untilMatch: 6,
    };
    const onStandIn = vi.fn();
    render(<ScoutForm {...stationProps({ standIn, onStandIn })} />);
    expect(screen.getByText("Zed")).toBeTruthy();
    expect(screen.getByText("Stand-in until match 6")).toBeTruthy();
    typeScouter("Sam");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByText("Team 101 saved");
    expect(persisted[0]?.doc).toMatchObject({ scoutedByName: "Zed" });
    expect("scoutedByUid" in (persisted[0]?.doc ?? {})).toBe(false);
  });

  it("clears the stand-in from the sheet", () => {
    const standIn: StandIn = {
      eventKey: "2027test",
      station: "R1",
      name: "Zed",
      uid: "",
      fromMatch: 1,
      untilMatch: 6,
    };
    const onStandIn = vi.fn();
    render(<ScoutForm {...stationProps({ standIn, onStandIn })} />);
    fireEvent.click(screen.getByRole("button", { name: "Not me? Switch" }));
    fireEvent.click(
      screen.getByRole("button", { name: "Back to the schedule" }),
    );
    expect(onStandIn).toHaveBeenCalledWith(null);
  });

  describe("when the schedule names nobody", () => {
    const empty = parseShifts({ roster: [{ uid: "a", name: "Ada" }] });

    it("asks who is scouting instead of naming anyone", () => {
      render(<ScoutForm {...stationProps({ shifts: empty })} />);
      expect(screen.getByText("Who is scouting?")).toBeTruthy();
      expect(screen.queryByText("Scouting as")).toBeNull();
      expect(screen.queryByText("Ada")).toBeNull();
      expect(
        screen.getByRole("button", { name: "Choose a name" }),
      ).toBeTruthy();
    });

    it("saves with no scout credited and the account as author", async () => {
      render(<ScoutForm {...stationProps({ shifts: empty })} />);
      typeScouter("Sam");
      fireEvent.click(screen.getByRole("button", { name: "Save" }));
      await screen.findByText("Team 101 saved");
      const doc = persisted[0]?.doc ?? {};
      expect(doc).toMatchObject({ authorUid: "uid-1" });
      expect("scoutedByName" in doc).toBe(false);
      expect("scoutedByUid" in doc).toBe(false);
    });

    it("takes a roster name for the next 6 matches", () => {
      const onStandIn = vi.fn();
      render(<ScoutForm {...stationProps({ shifts: empty, onStandIn })} />);
      fireEvent.click(screen.getByRole("button", { name: "Choose a name" }));
      fireEvent.click(
        within(screen.getByRole("dialog")).getByRole("button", { name: "Ada" }),
      );
      expect(onStandIn).toHaveBeenCalledWith({
        eventKey: "2027test",
        station: "R1",
        name: "Ada",
        uid: "a",
        fromMatch: 1,
        untilMatch: 6,
      });
    });

    it("credits nobody on a grid saved without stations", () => {
      const old = parseShifts({
        roster: [{ uid: "a", name: "Ada" }],
        rotations: [{ uid: "a", shifts: [{ startMatch: 1, endMatch: 6 }] }],
      });
      render(<ScoutForm {...stationProps({ shifts: old })} />);
      expect(screen.getByText("Who is scouting?")).toBeTruthy();
      expect(screen.queryByText("Ada")).toBeNull();
    });
  });
});

describe("Ctrl or Cmd+S", () => {
  const press = (init: KeyboardEventInit) => {
    const event = new KeyboardEvent("keydown", {
      key: "s",
      bubbles: true,
      cancelable: true,
      ...init,
    });
    window.dispatchEvent(event);
    return event;
  };

  it("saves like the button and blocks the browser's save dialog", async () => {
    render(<ScoutForm {...props()} />);
    typeScouter("Sam");
    const event = press({ ctrlKey: true });
    expect(event.defaultPrevented).toBe(true);
    expect(await screen.findByText("Team 101 saved")).toBeTruthy();
    expect(persisted).toHaveLength(1);
  });

  it("works with Cmd", async () => {
    render(<ScoutForm {...props()} />);
    typeScouter("Sam");
    press({ metaKey: true });
    expect(await screen.findByText("Team 101 saved")).toBeTruthy();
  });

  it("does not save when the button is disabled, but still blocks the dialog", () => {
    render(
      <ScoutForm {...props({ author: { uid: null, displayName: null } })} />,
    );
    const event = press({ ctrlKey: true });
    expect(event.defaultPrevented).toBe(true);
    expect(persisted).toHaveLength(0);
  });

  it("leaves a plain s and other shortcuts alone", () => {
    render(<ScoutForm {...props()} />);
    expect(press({}).defaultPrevented).toBe(false);
    expect(press({ ctrlKey: true, altKey: true }).defaultPrevented).toBe(false);
    expect(persisted).toHaveLength(0);
  });

  it("leaves the shortcut to the browser once the entry is saved", async () => {
    render(<ScoutForm {...props()} />);
    typeScouter("Sam");
    press({ ctrlKey: true });
    await screen.findByText("Team 101 saved");
    expect(press({ ctrlKey: true }).defaultPrevented).toBe(false);
    expect(persisted).toHaveLength(1);
  });
});

describe("event link line and pit bar", () => {
  it("says what the typed match links to, on the first step only", () => {
    render(<ScoutForm {...props()} />);
    expect(
      screen.getByText(
        "Scouting at 2027test. This entry links to 2027test_qm1 for accuracy checks.",
      ),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Auto" }));
    expect(screen.queryByText(/for accuracy checks/)).toBeNull();
  });

  it("docks a pit report bar for the team on the form", () => {
    const entry = {
      id: "p1",
      teamNumber: 101,
      eventKey: "2027test",
      fieldValues: {},
      authorUid: "u2",
      scoutName: "Pit Scout",
      updatedAt: "2027-03-01T10:00:00.000Z",
      photoKeys: [],
    };
    render(<ScoutForm {...props({ pit: { entries: [entry], config } })} />);
    expect(
      screen.getByRole("button", { name: /Pit report, Team 101/ }),
    ).toBeTruthy();
  });
});

describe("report drawing", () => {
  const fingerprint = JSON.stringify(
    config.sections.map((s) => [s.name, s.fields.map((f) => f.code)]),
  );
  const drawn = {
    teleop: [
      {
        phase: "teleop",
        colorValue: 4282384480,
        points: [
          { x: 0.1, y: 0.2 },
          { x: 0.6, y: 0.7 },
        ],
      },
    ],
  };

  it("shows on the last section, not the others", () => {
    render(<ScoutForm {...props()} />);
    expect(
      screen.queryByRole("heading", { name: "Report drawing" }),
    ).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Auto" }));
    expect(
      screen.getByRole("heading", { name: "Report drawing" }),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Review" }));
    expect(
      screen.queryByRole("heading", { name: "Report drawing" }),
    ).toBeNull();
  });

  it("is hidden when the config turns it off", () => {
    const off = parseConfig({
      ...JSON.parse(JSON.stringify(config)),
      report_drawing: false,
    });
    render(<ScoutForm {...props({ config: off })} />);
    fireEvent.click(screen.getByRole("button", { name: "Auto" }));
    expect(
      screen.queryByRole("heading", { name: "Report drawing" }),
    ).toBeNull();
  });

  it("saves a restored drawing as strokesByPhase", async () => {
    draftStore.set(fingerprint, { scouter: "Sam" }, drawn);
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByText("Team 101 saved");
    expect(persisted[0]?.doc.strokesByPhase).toEqual(drawn);
  });

  it("leaves strokesByPhase out when nothing was drawn", async () => {
    render(<ScoutForm {...props()} />);
    typeScouter("Sam");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByText("Team 101 saved");
    expect(persisted[0]?.doc).not.toHaveProperty("strokesByPhase");
  });

  it("does not send the drawing in the QR", async () => {
    draftStore.set(fingerprint, { scouter: "Sam" }, drawn);
    render(<ScoutForm {...props()} />);
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByText("Team 101 saved");
    expect(persisted[0]?.entry.qr).not.toContain("0.6");
  });
});
