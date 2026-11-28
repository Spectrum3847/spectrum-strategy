// @vitest-environment jsdom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import type { TeamComment } from "../team/format";
import { AiRewrite } from "./AiRewrite";
import type { AssistantApi } from "./firestore";
import { sharedWaitMs } from "./queue";

const state = vi.hoisted(() => ({ online: true, signedIn: true }));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({
    status: state.signedIn ? "signed-in" : "signed-out",
    uid: "u1",
  }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../ui/useOnline", () => ({ useOnline: () => state.online }));
vi.mock("./firestore", () => ({ firestoreApi: {} }));

const comments = (count: number): TeamComment[] =>
  Array.from({ length: count }, (_, i) => ({
    id: `e${i}:comments`,
    source: "Scout",
    text: `Comment ${i}`,
    fieldTitle: "Comments",
    scoutName: "Scout A",
    updatedAt: "2027-03-01T10:00:00Z",
    matchKey: `2027test_qm${i + 1}`,
  }));

const answer = {
  text: "Scouters agree this robot climbs reliably. They disagree on defence. ".repeat(
    2,
  ),
  model: "local-model",
  source: "local",
  coverage: 4,
  generatedAt: new Date().toISOString(),
};

function fakeApi(initial: Record<string, unknown> | null = null) {
  let push: (data: Record<string, unknown> | null) => void = () => undefined;
  const api = {
    watchSummary: vi.fn(
      (_id: string, onData: (data: Record<string, unknown> | null) => void) => {
        push = onData;
        onData(initial);
        return () => undefined;
      },
    ),
    post: vi.fn((_id: string, _doc: unknown) => Promise.resolve()),
    remove: vi.fn((_id: string) => Promise.resolve()),
  };
  return { api: api as AssistantApi & typeof api, push: (d: never) => push(d) };
}

const button = () =>
  screen.queryByRole("button", { name: "AI comment summary" });
const flush = () =>
  act(async () => {
    await vi.advanceTimersByTimeAsync(0);
  });

beforeEach(() => {
  state.online = true;
  state.signedIn = true;
  setRoles(ready("strategy"));
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

async function readyButton(name = "AI comment summary") {
  const button = (await screen.findByRole("button", {
    name,
  })) as HTMLButtonElement;
  await waitFor(() => expect(button.disabled).toBe(false));
  return button;
}

describe("AI comment summary", () => {
  it("shows nothing to a scouter", async () => {
    setRoles(ready("scouter"));
    const { api } = fakeApi();
    const { container } = render(
      <AiRewrite
        team={1111}
        eventKey="2027test"
        comments={comments(5)}
        api={api}
      />,
    );
    await new Promise((r) => setTimeout(r, 20));
    expect(container.textContent).toBe("");
  });

  it("shows nothing below the comment threshold", async () => {
    const { api } = fakeApi();
    const { container } = render(
      <AiRewrite
        team={1111}
        eventKey="2027test"
        comments={comments(3)}
        api={api}
      />,
    );
    await new Promise((r) => setTimeout(r, 20));
    expect(container.textContent).toBe("");
  });

  it("offers the button online and hides it offline", async () => {
    const { api } = fakeApi();
    const view = render(
      <AiRewrite
        team={1111}
        eventKey="2027test"
        comments={comments(5)}
        api={api}
      />,
    );
    expect(await readyButton()).toBeTruthy();
    state.online = false;
    view.rerender(
      <AiRewrite
        team={1111}
        eventKey="2027test"
        comments={comments(5)}
        api={api}
      />,
    );
    expect(button()).toBeNull();
  });

  it("shows a cached summary without posting a request", async () => {
    const { api } = fakeApi(answer);
    render(
      <AiRewrite
        team={1111}
        eventKey="2027test"
        comments={comments(5)}
        api={api}
      />,
    );
    expect(await screen.findByText("AI-written summary")).toBeTruthy();
    expect(screen.getByText(/climbs reliably/)).toBeTruthy();
    expect(screen.getByText(/Written from 4 of 5 comments/)).toBeTruthy();
    expect(button()).toBeNull();
    expect(api.post).not.toHaveBeenCalled();
  });

  it("posts the request, waits, and shows the answer when it arrives", async () => {
    const { api, push } = fakeApi();
    render(
      <AiRewrite
        team={1111}
        eventKey="2027test"
        comments={comments(5)}
        api={api}
      />,
    );
    fireEvent.click(await readyButton());
    expect(await screen.findByText(/Request sent/)).toBeTruthy();
    expect(api.post).toHaveBeenCalledTimes(1);
    const [id, doc] = api.post.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(id).toMatch(/^[0-9a-f]{64}$/);
    expect(doc.cacheKey).toBe("comment-digest:2027test:1111");
    expect(doc.requestedBy).toBe("u1");
    expect(doc.coverage).toBe(5);
    expect(String(doc.prompt)).toContain("- match Q1, by Scout A: Comment 0");

    act(() => push(answer as never));
    expect(await screen.findByText("AI-written summary")).toBeTruthy();
    expect(screen.queryByText(/Request sent/)).toBeNull();
    expect(api.remove).not.toHaveBeenCalled();
  });

  it("sends one request for a double tap", async () => {
    const { api } = fakeApi();
    render(
      <AiRewrite
        team={1111}
        eventKey="2027test"
        comments={comments(5)}
        api={api}
      />,
    );
    const button = await readyButton();
    fireEvent.click(button);
    fireEvent.click(button);
    expect(await screen.findByText(/Request sent/)).toBeTruthy();
    expect(api.post).toHaveBeenCalledTimes(1);
  });

  it("says the AI path is not available when nobody answers", async () => {
    const { api } = fakeApi();
    render(
      <AiRewrite
        team={1111}
        eventKey="2027test"
        comments={comments(5)}
        api={api}
      />,
    );
    const ask = await readyButton();
    vi.useFakeTimers();
    fireEvent.click(ask);
    await flush();
    expect(screen.getByText(/Request sent/)).toBeTruthy();
    await act(async () => {
      await vi.advanceTimersByTimeAsync(sharedWaitMs);
    });
    expect(screen.getByText(/The AI path is not available/)).toBeTruthy();
    expect(api.remove).toHaveBeenCalledTimes(1);
    expect(screen.getByRole("button", { name: "Try again" })).toBeTruthy();
  });

  it("reports a request that could not be sent", async () => {
    const { api } = fakeApi();
    api.post.mockRejectedValueOnce(
      new Error("Missing or insufficient permissions."),
    );
    render(
      <AiRewrite
        team={1111}
        eventKey="2027test"
        comments={comments(5)}
        api={api}
      />,
    );
    fireEvent.click(await readyButton());
    expect(
      await screen.findByText(
        /Could not send the request. Missing or insufficient/,
      ),
    ).toBeTruthy();
    expect(screen.getByRole("button", { name: "Try again" })).toBeTruthy();
  });
});
