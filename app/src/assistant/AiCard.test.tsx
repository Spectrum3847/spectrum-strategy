// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { AiCard } from "./AiCard";
import type { AssistantApi } from "./firestore";
import type { AssistantRequest } from "./queue";

vi.mock("../ui/useOnline", () => ({ useOnline: () => true }));
vi.mock("./firestore", () => ({ firestoreApi: {} }));

const request: AssistantRequest = {
  cacheKey: "k",
  system: "s",
  prompt: "p",
  minimumChars: 80,
  coverage: 2,
};
const answer = {
  text: "A long enough answer about the robot. ".repeat(3),
  model: "local-model",
  coverage: 2,
  generatedAt: new Date().toISOString(),
};

function api(initial: Record<string, unknown> | null) {
  const fake = {
    watchSummary: vi.fn(
      (_id: string, on: (d: Record<string, unknown> | null) => void) => {
        on(initial);
        return () => undefined;
      },
    ),
    post: vi.fn((_id: string, _doc: unknown) => Promise.resolve()),
    remove: vi.fn((_id: string) => Promise.resolve()),
  };
  return fake as AssistantApi & typeof fake;
}

const view = (
  fake: AssistantApi,
  over: Partial<Parameters<typeof AiCard>[0]> = {},
) =>
  render(
    <AiCard
      title="AI thing"
      idle="Ask."
      describe={(s) => `Written by ${s.model}.`}
      cacheKey="k"
      request={request}
      lead
      uid="u1"
      api={fake}
      {...over}
    />,
  );

afterEach(cleanup);

describe("AI card", () => {
  it("shows nothing to a reader who is not a lead", async () => {
    const { container } = view(api(null), { lead: false });
    await new Promise((r) => setTimeout(r, 20));
    expect(container.textContent).toBe("");
  });

  it("shows nothing without a key", async () => {
    const { container } = view(api(null), { cacheKey: null });
    await new Promise((r) => setTimeout(r, 20));
    expect(container.textContent).toBe("");
  });

  it("shows a cached answer without posting, even below the data floor", async () => {
    const fake = api(answer);
    view(fake, { request: null });
    expect(await screen.findByText(/A long enough answer/)).toBeTruthy();
    expect(screen.getByText("Written by local-model.")).toBeTruthy();
    expect(fake.post).not.toHaveBeenCalled();
  });

  it("hides the button below the data floor", async () => {
    const { container } = view(api(null), { request: null });
    await new Promise((r) => setTimeout(r, 20));
    expect(container.textContent).toBe("");
  });

  it("posts only on the button press", async () => {
    const fake = api(null);
    view(fake, { askLabel: "Go" });
    const button = (await screen.findByRole("button", {
      name: "Go",
    })) as HTMLButtonElement;
    await waitFor(() => expect(button.disabled).toBe(false));
    expect(fake.post).not.toHaveBeenCalled();
    fireEvent.click(button);
    expect(await screen.findByText(/Request sent/)).toBeTruthy();
    expect(fake.post).toHaveBeenCalledTimes(1);
  });
});
