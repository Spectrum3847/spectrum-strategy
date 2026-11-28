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
import { emptyRow } from "../teams/rows";
import { ChatView } from "./ChatPage";
import type { Facts } from "./chat";
import type { ChatApi } from "./chatSync";

const online = vi.hoisted(() => ({ value: true }));
vi.mock("../ui/useOnline", () => ({ useOnline: () => online.value }));
vi.mock("./chatSync", () => ({ chatApi: {} }));
vi.mock("./firestore", () => ({ firestoreApi: {} }));
vi.mock("./useChatFacts", () => ({ useChatFacts: () => ({}) }));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => [] }));
vi.mock("../auth/AuthProvider", () => ({ useAuth: () => ({}) }));
vi.mock("../training/session", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../training/session")>()),
  useTrainingSession: () => null,
}));

const facts: Facts = {
  eventKey: "2027test",
  team: 3847,
  rows: [
    {
      ...emptyRow(1111),
      nickname: "Alpha",
      listed: true,
      rank: 1,
      record: "3-0-0",
      epa: 50,
      matches: 3,
      total: 30,
      auto: 8,
      teleop: 22,
    },
  ],
  next: null,
  commentsOf: () => [],
};

const answer = {
  text: "Team 1111 scores about 30 points a match.",
  model: "local-model",
  generatedAt: new Date().toISOString(),
};

function fakeApi() {
  const api = {
    watchChats: vi.fn(() => () => undefined),
    saveChat: vi.fn(() => Promise.resolve("id")),
    deleteChat: vi.fn((_id: string) => Promise.resolve()),
  };
  let emit: ((event: import("./relay").ChatEvent) => void) | undefined;
  const transport = {
    ask: vi.fn(async (_request: unknown, callback: typeof emit) => {
      emit = callback;
    }),
    cancel: vi.fn(),
    close: vi.fn(),
  };
  return {
    api,
    transport,
    answer: () =>
      act(() => {
        emit?.({ type: "chunk", text: answer.text });
        emit?.({ type: "done", model: answer.model });
      }),
  };
}
let currentTransport: ReturnType<typeof fakeApi>["transport"];
const element = (api: ChatApi) => (
  <ChatView
    facts={facts}
    uid="u1"
    api={api}
    transport={currentTransport}
    deliveryOf={() => undefined}
    signedIn
  />
);
const view = (api: ChatApi) => {
  currentTransport = fakeApi().transport;
  return render(element(api));
};

const box = () => screen.getByLabelText("Your question") as HTMLTextAreaElement;
const type = (text: string) =>
  fireEvent.change(box(), { target: { value: text } });

beforeEach(() => {
  online.value = true;
  localStorage.clear();
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

describe("AI chat", () => {
  it("warns that a local model writes answers that can be wrong", () => {
    view(fakeApi().api);
    expect(screen.getByText(/can be wrong/)).toBeTruthy();
  });

  it("sends on Enter, streams the answer, and saves it", async () => {
    const { api } = fakeApi();
    view(api);
    type("How is 1111 scoring?");
    fireEvent.keyDown(box(), { key: "Enter", shiftKey: true });
    expect(currentTransport.ask).not.toHaveBeenCalled();
    fireEvent.keyDown(box(), { key: "Enter" });
    await waitFor(() => expect(currentTransport.ask).toHaveBeenCalledTimes(1));
    const request = currentTransport.ask.mock.calls[0]?.[0] as {
      prompt: string;
    };
    expect(request.prompt).toContain(
      "Question from the lead: How is 1111 scoring?",
    );
    const callback = currentTransport.ask.mock.calls[0]?.[1];
    act(() => callback?.({ type: "chunk", text: answer.text }));
    expect(screen.getByText(answer.text)).toBeTruthy();
    act(() => callback?.({ type: "done", model: answer.model }));
    await waitFor(() => expect(api.saveChat).toHaveBeenCalledTimes(1));
  });

  it("gives the question back when canceled", async () => {
    view(fakeApi().api);
    type("Anyone good?");
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    fireEvent.click(await screen.findByRole("button", { name: "Cancel" }));
    expect(box().value).toBe("Anyone good?");
    expect(currentTransport.cancel).toHaveBeenCalled();
  });

  it("cancels a question when the connection drops and asks again when it returns", async () => {
    const { api } = fakeApi();
    const { rerender } = view(api);
    type("Anyone good?");
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await waitFor(() => expect(currentTransport.ask).toHaveBeenCalledTimes(1));

    online.value = false;
    rerender(element(api));
    expect(
      screen.getByText(
        "You are offline. The question is sent again when you reconnect.",
      ),
    ).toBeTruthy();
    expect(screen.getByRole("button", { name: "Cancel" })).toBeTruthy();
    expect(currentTransport.cancel).toHaveBeenCalled();
    expect(currentTransport.ask).toHaveBeenCalledTimes(1);

    online.value = true;
    rerender(element(api));
    await waitFor(() => expect(currentTransport.ask).toHaveBeenCalledTimes(2));
    expect(screen.getByText("Connecting to a relay.")).toBeTruthy();
  });

  it("does not send offline", () => {
    online.value = false;
    view(fakeApi().api);
    type("Anyone good?");
    expect(screen.getByText(/You are offline/)).toBeTruthy();
    expect(
      (screen.getByRole("button", { name: "Send" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
  });

  it("opens a saved chat from this device", () => {
    localStorage.setItem(
      "ss.ai.chats.u1",
      JSON.stringify([
        {
          id: "old",
          title: "Earlier question",
          createdAt: "2027-03-01T10:00:00.000Z",
          updatedAt: "2027-03-01T10:00:00.000Z",
          messages: [
            { kind: "user", text: "Earlier question" },
            { kind: "assistant", text: "Earlier answer.", model: "m" },
          ],
          turns: [],
        },
      ]),
    );
    view(fakeApi().api);
    fireEvent.change(screen.getByLabelText("Chat"), {
      target: { value: "old" },
    });
    expect(screen.getByText("Earlier answer.")).toBeTruthy();
  });

  it("keeps a chat deleted here out after a later remote snapshot", () => {
    const saved = {
      id: "old",
      title: "Earlier question",
      createdAt: "2027-03-01T10:00:00.000Z",
      updatedAt: "2027-03-01T10:00:00.000Z",
      messages: [
        { kind: "user", text: "Earlier question" },
        { kind: "assistant", text: "Earlier answer.", model: "m" },
      ],
      turns: [],
    };
    localStorage.setItem("ss.ai.chats.u1", JSON.stringify([saved]));
    const { api } = fakeApi();
    let push: ((chats: unknown[]) => void) | undefined;
    api.watchChats.mockImplementation(((
      _uid: string,
      on: (chats: unknown[]) => void,
    ) => {
      push = on;
      return () => undefined;
    }) as never);
    view(api);
    fireEvent.change(screen.getByLabelText("Chat"), {
      target: { value: "old" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Delete chat" }));
    expect(api.deleteChat).toHaveBeenCalledWith("old");
    act(() => push?.([saved]));
    const options = screen
      .getAllByRole("option")
      .map((o) => (o as HTMLOptionElement).value);
    expect(options).not.toContain("old");
  });

  it("says when chats from other devices cannot load", () => {
    const { api } = fakeApi();
    api.watchChats.mockImplementation(((
      _uid: string,
      _on: unknown,
      onError: () => void,
    ) => {
      onError();
      return () => undefined;
    }) as never);
    view(api);
    expect(
      screen.getByText(/Chats from your other devices could not load/),
    ).toBeTruthy();
  });
});
