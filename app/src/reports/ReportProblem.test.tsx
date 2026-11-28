// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { ReportProblem } from "./ReportProblem";

const state = vi.hoisted(() => ({
  status: "signed-in" as string,
  outbox: [] as unknown[],
  enqueue: vi.fn((..._args: unknown[]) => Promise.resolve("item1")),
  upload: vi.fn<(...args: unknown[]) => Promise<unknown>>(() =>
    Promise.resolve({ type: "response", status: 201, key: "shot.jpg" }),
  ),
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({
    status: state.status,
    uid: state.status === "signed-in" ? "u1" : null,
    displayName: "Scout A",
  }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../outbox/outbox", () => ({
  enqueueWrite: (...args: unknown[]) =>
    (state.enqueue as (...a: unknown[]) => Promise<string>)(...args),
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));
vi.mock("../photos/compress", () => ({
  preparePhoto: (file: File) => Promise.resolve(file),
}));
vi.mock("../photos/service", () => ({
  uploadPhoto: (...args: unknown[]) =>
    (state.upload as (...a: unknown[]) => Promise<unknown>)(...args),
}));

beforeEach(() => {
  state.status = "signed-in";
  state.outbox = [];
  state.enqueue.mockClear();
  state.upload.mockClear();
  setRoles(ready("scouter"));
});
afterEach(cleanup);

describe("report a problem", () => {
  it("writes a bug report through the outbox", async () => {
    render(<ReportProblem />);
    const send = screen.getByRole("button", {
      name: "Send report",
    }) as HTMLButtonElement;
    expect(send.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText("Area"), {
      target: { value: "Pit scouting" },
    });
    fireEvent.change(screen.getByLabelText("Impact"), {
      target: { value: "Cosmetic issue" },
    });
    fireEvent.change(screen.getByLabelText("Summary"), {
      target: { value: "Pit form froze" },
    });
    fireEvent.change(screen.getByLabelText("What happened"), {
      target: { value: "Tapped Save, nothing moved." },
    });
    fireEvent.click(send);
    await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(1));
    const [path, doc, label] = state.enqueue.mock.calls[0] as [
      string,
      Record<string, unknown>,
      string,
    ];
    expect(path).toBe(`bugReports/${doc.id}`);
    expect(label).toBe("Problem report");
    expect(doc).toMatchObject({
      title: "Pit form froze",
      body: "Tapped Save, nothing moved.",
      reporterUid: "u1",
      reporterName: "Scout A",
      roles: "Scouter",
      kind: "bug",
      area: "Pit scouting",
      impact: "Cosmetic issue",
      platform: "web",
      status: "new",
    });
    expect((screen.getByLabelText("Summary") as HTMLInputElement).value).toBe(
      "",
    );
  });

  it("sends feedback without an impact", async () => {
    render(<ReportProblem />);
    fireEvent.click(screen.getByRole("button", { name: "Feedback" }));
    expect(screen.queryByLabelText("Impact")).toBeNull();
    fireEvent.change(screen.getByLabelText("Summary"), {
      target: { value: "Bigger buttons" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Send report" }));
    await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(1));
    const doc = state.enqueue.mock.calls[0]?.[1] as Record<string, unknown>;
    expect(doc.kind).toBe("feedback");
    expect("impact" in doc).toBe(false);
  });

  it("shows where the sent report stands", async () => {
    state.outbox = [{ id: "item1", path: "bugReports/x", status: "on-device" }];
    render(<ReportProblem />);
    fireEvent.change(screen.getByLabelText("Summary"), {
      target: { value: "Something" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Send report" }));
    expect(await screen.findByText("On this device")).toBeTruthy();
  });

  it("says what is attached", () => {
    render(<ReportProblem />);
    expect(screen.getByText(/app version/)).toBeTruthy();
  });

  const pickShots = (...names: string[]) => {
    const input = document.querySelector(
      'input[type="file"]',
    ) as HTMLInputElement;
    const files = names.map((n) => new File(["x"], n, { type: "image/png" }));
    fireEvent.change(input, { target: { files } });
  };

  const sendWith = (title: string) => {
    fireEvent.change(screen.getByLabelText("Summary"), {
      target: { value: title },
    });
    fireEvent.click(screen.getByRole("button", { name: "Send report" }));
  };

  it("uploads the screenshots and writes their keys", async () => {
    render(<ReportProblem />);
    pickShots("one.png", "two.png");
    expect(screen.getByText("one.png")).toBeTruthy();
    sendWith("Board blank");
    await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(1));
    expect(state.upload).toHaveBeenCalledTimes(2);
    const doc = state.enqueue.mock.calls[0]?.[1] as Record<string, unknown>;
    expect(doc.screenshotKeys).toEqual(["shot.jpg", "shot.jpg"]);
    await waitFor(() => expect(screen.queryByText("one.png")).toBeNull());
  });

  it("keeps at most three and lets one be removed", () => {
    render(<ReportProblem />);
    pickShots("1.png", "2.png", "3.png", "4.png");
    expect(screen.queryByText("4.png")).toBeNull();
    expect(
      (
        screen.getByRole("button", {
          name: "Add screenshot",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
    fireEvent.click(screen.getByRole("button", { name: "Remove 2.png" }));
    expect(screen.queryByText("2.png")).toBeNull();
    expect(
      (
        screen.getByRole("button", {
          name: "Add screenshot",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(false);
  });

  it("sends the report without a screenshot that could not upload", async () => {
    state.upload.mockResolvedValueOnce({
      type: "unavailable",
      reason: "offline",
    });
    render(<ReportProblem />);
    pickShots("one.png");
    sendWith("Board blank");
    await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(1));
    const doc = state.enqueue.mock.calls[0]?.[1] as Record<string, unknown>;
    expect("screenshotKeys" in doc).toBe(false);
    expect(
      await screen.findByText(/1 screenshot could not be attached/),
    ).toBeTruthy();
  });

  it("is hidden from a viewer", () => {
    setRoles(ready("viewer"));
    render(<ReportProblem />);
    expect(
      screen.queryByRole("heading", { name: "Report a problem" }),
    ).toBeNull();
  });

  it("is hidden from a mentor, whose write the rules would refuse", () => {
    setRoles(ready("mentor"));
    render(<ReportProblem />);
    expect(
      screen.queryByRole("heading", { name: "Report a problem" }),
    ).toBeNull();
  });

  it("will not send without a sign-in", () => {
    state.status = "signed-out";
    render(<ReportProblem />);
    fireEvent.change(screen.getByLabelText("Summary"), {
      target: { value: "Something" },
    });
    expect(
      (screen.getByRole("button", { name: "Send report" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
    expect(screen.getByText("Sign in to send a report.")).toBeTruthy();
  });

  it("says when the report did not reach this device", async () => {
    state.enqueue.mockRejectedValueOnce(new Error("no storage"));
    render(<ReportProblem />);
    fireEvent.change(screen.getByLabelText("Summary"), {
      target: { value: "Something" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Send report" }));
    expect(
      await screen.findByText("Could not save on this device. Try again."),
    ).toBeTruthy();
    expect((screen.getByLabelText("Summary") as HTMLInputElement).value).toBe(
      "Something",
    );
  });
});
