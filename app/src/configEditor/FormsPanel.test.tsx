// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { FormsPanel } from "./FormsPanel";

const state = vi.hoisted(() => ({
  save: vi.fn((..._args: unknown[]) => Promise.resolve("item1")),
  outbox: [] as unknown[],
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({ status: "signed-in", uid: "u1" }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));
vi.mock("./source", async () => {
  const scout = (await import("../../../assets/scout_config_default.json"))
    .default;
  const pit = (await import("../../../assets/pit_scout_config_default.json"))
    .default;
  const prescout = (
    await import("../../../assets/prescout_config_default.json")
  ).default;
  const active = { scout, pit, prescout };
  return {
    useConfigSource: (form: keyof typeof active) => ({
      active: active[form],
      teamCopyKnown: true,
    }),
    saveConfig: (...args: unknown[]) => state.save(...args),
  };
});

const valid = JSON.stringify({
  title: "Custom",
  delimiter: "\t",
  sections: [
    {
      name: "Auto",
      fields: [{ title: "Start", type: "text", code: "start" }],
    },
  ],
});

const pasteJson = (text: string) => {
  fireEvent.click(screen.getByRole("button", { name: "Paste JSON" }));
  fireEvent.change(screen.getByLabelText("Config JSON"), {
    target: { value: text },
  });
  fireEvent.click(screen.getByRole("button", { name: "Check and load" }));
};

const savedJson = () => {
  const call = state.save.mock.calls[0];
  return { form: call?.[0], doc: JSON.parse(String(call?.[1])) };
};

beforeEach(() => {
  state.save.mockClear();
  state.outbox = [];
  setRoles(ready("strategy"));
});

afterEach(cleanup);

describe("a lead loading JSON", () => {
  it("shows why an invalid config is refused and does not stage it", () => {
    render(<FormsPanel />);
    pasteJson("[]");
    expect(screen.getByRole("alert").textContent).toContain(
      "Config JSON must be an object.",
    );
    expect(
      screen.queryByRole("button", { name: "Review and save" }),
    ).toBeNull();
    expect(screen.queryByText("Unsaved changes")).toBeNull();
  });

  it("refuses colliding select options", () => {
    render(<FormsPanel />);
    pasteJson(
      JSON.stringify({
        title: "Bad",
        sections: [
          {
            name: "Auto",
            fields: [
              {
                title: "Start",
                type: "select",
                code: "start",
                choices: { Left: "same", Right: "same" },
              },
            ],
          },
        ],
      }),
    );
    expect(screen.getByRole("alert").textContent).toContain(
      'Select field "start" has duplicate option values',
    );
    expect(state.save).not.toHaveBeenCalled();
  });

  it("names the changes, then writes the whole document on confirm", async () => {
    render(<FormsPanel />);
    pasteJson(valid);
    expect(screen.getByText("Unsaved changes")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Review and save" }));
    expect(screen.getByText(/every device on the team/)).toBeTruthy();
    expect(screen.getByText("Fields removed")).toBeTruthy();
    expect(screen.getByText("Fields added")).toBeTruthy();
    expect(state.save).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Save to the team" }));
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    const { form, doc } = savedJson();
    expect(form).toBe("scout");
    expect(doc.title).toBe("Custom");
    expect(doc.revision).toBe(5);
    expect(screen.queryByText("Unsaved changes")).toBeNull();
  });

  it("loads an uploaded file through the same checks", async () => {
    render(<FormsPanel />);
    const input = screen.getByLabelText("Scout form JSON file");
    Object.defineProperty(input, "files", {
      value: [{ name: "form.json", text: () => Promise.resolve(valid) }],
    });
    fireEvent.change(input);
    await screen.findByText(/form.json: "Custom" with 1 fields in 1 sections/);
    expect(
      screen.getByRole("button", { name: "Review and save" }),
    ).toBeTruthy();
  });

  it("shows a refused save and keeps the draft", async () => {
    state.save.mockImplementationOnce(() =>
      Promise.reject(new Error("Training mode: nothing is saved.")),
    );
    render(<FormsPanel />);
    pasteJson(valid);
    fireEvent.click(screen.getByRole("button", { name: "Review and save" }));
    fireEvent.click(screen.getByRole("button", { name: "Save to the team" }));
    await screen.findByText("Training mode: nothing is saved.");
    expect(screen.getByText("Unsaved changes")).toBeTruthy();
  });

  it("discards a draft", () => {
    render(<FormsPanel />);
    pasteJson(valid);
    fireEvent.click(screen.getByRole("button", { name: "Discard changes" }));
    expect(screen.queryByText("Unsaved changes")).toBeNull();
  });
});

describe("the pit form question editor", () => {
  const openPit = () => {
    render(<FormsPanel />);
    fireEvent.click(screen.getByRole("button", { name: "Pit form" }));
  };

  it("adds a question and saves it with a raised revision", async () => {
    openPit();
    fireEvent.click(
      screen.getByRole("button", { name: "Add question to Drivetrain" }),
    );
    fireEvent.change(screen.getByLabelText("Question"), {
      target: { value: "Bumper Color" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Add question" }));
    expect(
      within(screen.getByRole("region", { name: "Drivetrain" })).getByText(
        "Bumper Color",
      ),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Review and save" }));
    expect(screen.getByText("Fields added").nextSibling?.textContent).toBe(
      "Bumper Color",
    );
    fireEvent.click(screen.getByRole("button", { name: "Save to the team" }));
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    const { form, doc } = savedJson();
    expect(form).toBe("pit");
    expect(doc.revision).toBe(7);
    const codes = doc.sections.flatMap((s: { fields: { code: string }[] }) =>
      s.fields.map((f) => f.code),
    );
    expect(codes).toContain("bumperColor");
  });

  it("retires a removed choice and says so before saving", async () => {
    openPit();
    fireEvent.click(screen.getByRole("button", { name: "Edit Drive train" }));
    fireEvent.click(screen.getByRole("button", { name: "Remove Tank" }));
    expect(screen.getByText("Tank (retired)")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));
    fireEvent.click(screen.getByRole("button", { name: "Review and save" }));
    expect(screen.getByText("Choices retired").nextSibling?.textContent).toBe(
      "Drive train: Tank",
    );
    fireEvent.click(screen.getByRole("button", { name: "Save to the team" }));
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    const { doc } = savedJson();
    const field = doc.sections
      .flatMap((s: { fields: Record<string, unknown>[] }) => s.fields)
      .find((f: Record<string, unknown>) => f.code === "drivetrainType");
    expect(field.retiredChoiceKeys).toEqual(["tank"]);
    expect(field.choices.tank).toBe("Tank");
  });

  it("will not remove the last choice", () => {
    openPit();
    fireEvent.click(screen.getByRole("button", { name: "Edit Drive train" }));
    fireEvent.click(screen.getByRole("button", { name: "Remove Tank" }));
    fireEvent.click(screen.getByRole("button", { name: "Remove Swerve" }));
    const last = screen.getByRole("button", { name: "Remove Other" });
    expect(last.hasAttribute("disabled")).toBe(true);
  });

  it("keeps a section with questions from being deleted", () => {
    openPit();
    const button = screen.getByRole("button", {
      name: "Delete section Drivetrain",
    });
    expect(button.hasAttribute("disabled")).toBe(true);
  });

  it("adds a section", () => {
    openPit();
    fireEvent.change(screen.getByLabelText("Section name"), {
      target: { value: "Extras" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Add section" }));
    expect(screen.getByRole("heading", { name: "Extras" })).toBeTruthy();
  });
});

describe("the scout form", () => {
  it("edits a field's title and description only", () => {
    render(<FormsPanel />);
    const edit = screen.getAllByRole("button", { name: /^Edit / })[0];
    if (!edit) throw new Error("no edit button");
    fireEvent.click(edit);
    expect(screen.queryByLabelText("Type")).toBeNull();
    expect(screen.queryByText("Required")).toBeNull();
    fireEvent.change(screen.getByLabelText("Title"), {
      target: { value: "Renamed field" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));
    fireEvent.click(screen.getByRole("button", { name: "Review and save" }));
    expect(screen.getByText("Fields edited").nextSibling?.textContent).toBe(
      "Renamed field",
    );
    expect(screen.queryByRole("button", { name: /^Remove / })).toBeNull();
  });

  it("toggles the report drawing", () => {
    render(<FormsPanel />);
    fireEvent.click(screen.getByLabelText(/Report drawing/));
    fireEvent.click(screen.getByRole("button", { name: "Review and save" }));
    expect(screen.getByText("Settings changed").nextSibling?.textContent).toBe(
      "Report drawing",
    );
  });
});

describe("the prescout form", () => {
  it("can load JSON but has no question editor", () => {
    render(<FormsPanel />);
    fireEvent.click(screen.getByRole("button", { name: "Prescout form" }));
    expect(
      screen.getByRole("button", { name: "Upload JSON file" }),
    ).toBeTruthy();
    expect(screen.queryByRole("button", { name: /^Edit / })).toBeNull();
  });
});

describe("everyone else", () => {
  it("reads the forms without any way to change them", () => {
    setRoles(ready("scouter"));
    render(<FormsPanel />);
    expect(screen.getByRole("heading", { name: "Team forms" })).toBeTruthy();
    expect(screen.getByText(/Your team leads manage this form/)).toBeTruthy();
    expect(
      screen.queryByRole("button", { name: "Upload JSON file" }),
    ).toBeNull();
    expect(screen.queryByRole("button", { name: "Paste JSON" })).toBeNull();
    expect(screen.queryByRole("button", { name: /^Edit / })).toBeNull();
    expect(screen.queryByLabelText(/Report drawing/)).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Pit form" }));
    expect(screen.queryByRole("button", { name: /^Edit / })).toBeNull();
    expect(
      within(screen.getByRole("region", { name: "Drivetrain" })).getByText(
        "Drive train",
      ),
    ).toBeTruthy();
  });

  it("is read only while the role is still loading", () => {
    setRoles({
      status: "loading",
      retry: () => undefined,
    });
    render(<FormsPanel />);
    expect(screen.queryByRole("button", { name: "Paste JSON" })).toBeNull();
  });
});
