// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import type { EventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import { ExportPanel } from "./ExportPanel";

const state = vi.hoisted(() => ({
  eventKey: "2027test",
  entries: [] as unknown[],
  ready: true,
  failed: false,
  download: vi.fn(),
}));

vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../data/useCorrections", () => ({
  useCorrections: () => ({ items: [], ready: true, failed: false }),
}));
vi.mock("../data/entries", () => ({
  useEventEntries: () => ({
    items: state.entries,
    ready: state.ready,
    failed: state.failed,
  }),
}));
vi.mock("../data/useTbaEvent", () => ({ useTbaEvent: () => ({ teams: [] }) }));
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({
    eventKey: state.eventKey,
    config: parseConfig({
      sections: [
        {
          name: "A",
          fields: [
            { code: "fuel", title: "Fuel", type: "counter" },
            { code: "comments", title: "Comments", type: "text" },
          ],
        },
      ],
    }),
  }),
}));
vi.mock("./download", () => ({ downloadCsv: state.download }));

const entry = (id: string, scoutName: string): EventEntry => ({
  id,
  tbaMatchKey: `2027test_qm${id}`,
  teamNumber: 1111,
  alliance: "Red",
  scoutName,
  updatedAt: "2027-03-05T18:00:00.000Z",
  fieldValues: { fuel: 3, comments: "slow" },
});

beforeEach(() => {
  setRoles(ready("strategy"));
  state.eventKey = "2027test";
  state.entries = [entry("1", "Sam Scout"), entry("2", "Pat Scout")];
  state.ready = true;
  state.failed = false;
  state.download.mockClear();
});
afterEach(cleanup);

describe("ExportPanel", () => {
  it("is hidden from scouts", () => {
    setRoles(ready("scouter"));
    const { container } = render(<ExportPanel />);
    expect(container.firstChild).toBeNull();
  });

  it("starts with names hidden and comments off, and says how many entries", () => {
    render(<ExportPanel />);
    expect(
      (screen.getByLabelText(/Hide scout names/) as HTMLInputElement).checked,
    ).toBe(true);
    expect(
      (screen.getByLabelText(/Include comments/) as HTMLInputElement).checked,
    ).toBe(false);
    expect(screen.getByRole("status").textContent).toBe(
      "2 entries for 2027test.",
    );
  });

  it("downloads a file named after the event with names hidden", () => {
    render(<ExportPanel />);
    fireEvent.click(screen.getByRole("button", { name: "Download CSV" }));
    const [name, csv] = state.download.mock.calls[0] as [string, string];
    expect(name).toBe("2027test-scout-entries.csv");
    expect(csv).toContain("Scout 1");
    expect(csv).not.toContain("Sam Scout");
    expect(csv).not.toContain("slow");
  });

  it("downloads the team summary, which has no scout names", () => {
    render(<ExportPanel />);
    fireEvent.click(
      screen.getByRole("button", { name: "Download team summary" }),
    );
    const [name, csv] = state.download.mock.calls[0] as [string, string];
    expect(name).toBe("2027test-team-summary.csv");
    expect(csv.split("\r\n")[1]).toMatch(/^2027test,1111,/);
    expect(csv).not.toContain("Sam Scout");
  });

  it("includes names and comments when asked", () => {
    render(<ExportPanel />);
    fireEvent.click(screen.getByLabelText(/Hide scout names/));
    fireEvent.click(screen.getByLabelText(/Include comments/));
    fireEvent.click(screen.getByRole("button", { name: "Download CSV" }));
    const csv = (state.download.mock.calls[0] as [string, string])[1];
    expect(csv).toContain("Sam Scout");
    expect(csv).toContain("slow");
  });

  it("disables Download with no entries or no event", () => {
    state.entries = [];
    const { rerender } = render(<ExportPanel />);
    expect(
      (
        screen.getByRole("button", {
          name: "Download CSV",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
    state.eventKey = "";
    state.entries = [entry("1", "Sam Scout")];
    rerender(<ExportPanel />);
    expect(screen.getByRole("status").textContent).toMatch(/Set an event/);
    expect(
      (
        screen.getByRole("button", {
          name: "Download CSV",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
  });

  it("warns when the entries may be incomplete", () => {
    state.failed = true;
    render(<ExportPanel />);
    expect(screen.getByRole("alert").textContent).toMatch(/incomplete/);
  });
});
