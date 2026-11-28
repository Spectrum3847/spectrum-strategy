// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { PostMatchSection } from "./PostMatchSection";
import { emptyReport, type PostMatchReport } from "./postMatch";

const state = vi.hoisted(() => ({
  reports: [] as unknown[],
  failed: false,
  outbox: [] as unknown[],
  save: vi.fn((..._args: unknown[]) => Promise.resolve("item1")),
}));

vi.mock("./usePostMatchReports", () => ({
  usePostMatchReports: () => ({
    items: state.reports,
    ready: true,
    failed: state.failed,
  }),
  reportPath: (id: string) => `postMatchReports/${id}`,
  savePostMatchReport: (...args: unknown[]) =>
    (state.save as (...a: unknown[]) => Promise<string>)(...args),
}));
vi.mock("../assistant/AiCard", () => ({
  AiCard: (props: { lead: boolean; request: unknown }) => (
    <p>{`ai lead=${props.lead} request=${props.request !== null}`}</p>
  ),
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));

const author = { uid: "u1", displayName: "Lead A" };

const view = (props: Partial<Parameters<typeof PostMatchSection>[0]> = {}) =>
  render(
    <PostMatchSection
      eventKey="2027test"
      matchKey="2027test_qm14"
      label="Q14"
      canEdit
      signedIn
      author={author}
      match={{
        red: [1111],
        blue: [2222],
        redScore: 10,
        blueScore: 5,
        winner: "red",
      }}
      us={1111}
      {...props}
    />,
  );

const written: PostMatchReport = {
  ...emptyReport("2027test", "qm14"),
  auto: "Scored two",
  notes: "Lost comms",
  authorUid: "u2",
  authorDisplayName: "Lead B",
  updatedMs: 5,
};

beforeEach(() => {
  state.reports = [];
  state.failed = false;
  state.outbox = [];
  state.save.mockClear();
});
afterEach(cleanup);

describe("post match report", () => {
  it("shows four sections and saves them as one report", async () => {
    view();
    expect(
      screen.getByRole("heading", { name: "Post match report" }),
    ).toBeTruthy();
    const save = screen.getByRole("button", {
      name: "Save report",
    }) as HTMLButtonElement;
    expect(save.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText("Auto"), {
      target: { value: "Left start" },
    });
    fireEvent.change(screen.getByLabelText("Notes"), {
      target: { value: "Penalty" },
    });
    expect(save.disabled).toBe(false);
    fireEvent.click(save);
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    const [prev, sections, who, label] = state.save.mock.calls[0] as [
      PostMatchReport,
      Record<string, string>,
      unknown,
      string,
    ];
    expect(prev.id).toBe("2027test_qm14");
    expect(sections).toEqual({
      auto: "Left start",
      teleop: "",
      endgame: "",
      notes: "Penalty",
    });
    expect(who).toEqual(author);
    expect(label).toBe("Report for Q14");
  });

  it("shows the saved report, its writer and where it stands", () => {
    state.reports = [written];
    state.outbox = [
      { id: "i1", path: "postMatchReports/2027test_qm14", status: "sending" },
    ];
    view();
    expect((screen.getByLabelText("Auto") as HTMLTextAreaElement).value).toBe(
      "Scored two",
    );
    expect(screen.getByText("Last written by Lead B")).toBeTruthy();
    expect(screen.getByText("Sending")).toBeTruthy();
  });

  it("is read only for a member who cannot write it", () => {
    state.reports = [written];
    view({ canEdit: false });
    expect(screen.queryByRole("button", { name: "Save report" })).toBeNull();
    expect(
      (screen.getByLabelText("Auto") as HTMLTextAreaElement).readOnly,
    ).toBe(true);
    expect(
      screen.getByText(/Only strategy leads and admins can write this/),
    ).toBeTruthy();
  });

  it("offers the AI summary to a writer once something is written", () => {
    state.reports = [written];
    view();
    expect(screen.getByText("ai lead=true request=true")).toBeTruthy();
  });

  it("has no request for an empty report", () => {
    view();
    expect(screen.getByText("ai lead=true request=false")).toBeTruthy();
  });

  it("says nobody has written it up yet", () => {
    view({ canEdit: false });
    expect(screen.getByText(/Nobody has written it up yet/)).toBeTruthy();
  });

  it("will not save without a sign-in", () => {
    view({ signedIn: false, author: { uid: "", displayName: "" } });
    fireEvent.change(screen.getByLabelText("Auto"), {
      target: { value: "x" },
    });
    expect(
      (screen.getByRole("button", { name: "Save report" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
    expect(screen.getByText("Sign in to save the report.")).toBeTruthy();
  });

  it("says when the save did not reach this device", async () => {
    state.save.mockRejectedValueOnce(new Error("no storage"));
    view();
    fireEvent.change(screen.getByLabelText("Teleop"), {
      target: { value: "x" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save report" }));
    expect(
      await screen.findByText("Could not save on this device. Try again."),
    ).toBeTruthy();
  });

  it("warns when the saved report could not be read", () => {
    state.failed = true;
    view();
    expect(screen.getByText(/Could not read the saved report/)).toBeTruthy();
  });
});
