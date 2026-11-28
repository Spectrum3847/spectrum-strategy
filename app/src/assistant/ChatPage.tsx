import {
  type KeyboardEvent,
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import { Link } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { useOutbox } from "../outbox/useOutbox";
import { type Delivery, DeliveryLine } from "../scout/ScoutForm";
import { useTrainingSession } from "../training/session";
import { useOnline } from "../ui/useOnline";
import { ChatTurn } from "./ChatTurn";
import {
  chatKey,
  chatRequest,
  displayTitle,
  type Facts,
  maxQuestionChars,
  mergeSessions,
  newSession,
  type Session,
  withExchange,
} from "./chat";
import { loadChats, loadDeleted, saveChats, saveDeleted } from "./chatStore";
import { type ChatApi, chatApi } from "./chatSync";
import { type AiSummary, type AssistantRequest, ago } from "./queue";
import type { RelayChat } from "./relay";
import { newRelayChat } from "./relayChat";
import { useChatFacts } from "./useChatFacts";
import "./assistant.css";

interface Pending {
  sessionId: string;
  question: string;
  key: string;
  request: AssistantRequest;
}

export function AiChat() {
  const auth = useAuth();
  const facts = useChatFacts();
  const outbox = useOutbox();
  const uid = auth.status === "signed-in" ? (auth.uid ?? "") : "";
  const deliveryOf = (path: string): Delivery | undefined => {
    const item = outbox.find((i) => i.path === path);
    return (
      item && { status: item.status, ...(item.error && { error: item.error }) }
    );
  };
  if (uid === "") return null;
  return (
    <ChatView
      facts={facts}
      uid={uid}
      api={chatApi}
      deliveryOf={deliveryOf}
      signedIn
    />
  );
}

interface ViewProps {
  facts: Facts;
  uid: string;
  api: ChatApi;
  deliveryOf(path: string): Delivery | undefined;
  signedIn: boolean;
  transport?: RelayChat;
}

export function ChatView({
  facts,
  uid,
  api,
  deliveryOf,
  signedIn,
  transport,
}: ViewProps) {
  const [relay] = useState(() => transport ?? newRelayChat());
  useEffect(() => () => relay.close(), [relay]);
  const online = useOnline();
  const training = useTrainingSession() !== null;
  const [sessions, setSessions] = useState<Session[]>(() => [
    newSession(crypto.randomUUID(), new Date()),
    ...loadChats(uid),
  ]);
  const [activeId, setActiveId] = useState(() => sessions[0]?.id ?? "");
  const [draft, setDraft] = useState("");
  const [pending, setPending] = useState<Pending | null>(null);
  const [notice, setNotice] = useState("");
  const [syncFailed, setSyncFailed] = useState(false);
  const latest = useRef({ sessions, pending });
  latest.current = { sessions, pending };

  const active = sessions.find((s) => s.id === activeId) ?? sessions[0];

  useEffect(() => {
    saveChats(
      uid,
      sessions.filter((s) => s.messages.length > 0),
    );
  }, [uid, sessions]);

  useEffect(() => {
    for (const id of loadDeleted(uid))
      api.deleteChat(id).catch(() => undefined);
    return api.watchChats(
      uid,
      (remote) => {
        const gone = new Set(loadDeleted(uid));
        setSessions((held) =>
          mergeSessions(
            held,
            remote.filter((s) => !gone.has(s.id)),
          ),
        );
      },
      () => setSyncFailed(true),
    );
  }, [api, uid]);

  const answered = useCallback(
    (summary: AiSummary) => {
      const { sessions: held, pending: turn } = latest.current;
      const session = held.find((s) => s.id === turn?.sessionId);
      if (!turn || !session) return;
      const next = withExchange(session, turn.question, summary, new Date());
      setSessions((all) =>
        mergeSessions(
          all.filter((s) => s.id !== next.id),
          [next],
        ),
      );
      setPending(null);
      api.saveChat(next, uid).catch(() => undefined);
    },
    [api, uid],
  );

  const cancel = useCallback(() => {
    const turn = latest.current.pending;
    if (!turn) return;
    setDraft(turn.question);
    setPending(null);
    relay.cancel();
  }, [relay]);

  const open = (id: string) => {
    if (pending) return;
    setActiveId(id);
    setNotice("");
  };

  const startChat = () => {
    if (pending) return;
    const blank = sessions.find((s) => s.messages.length === 0);
    if (blank) return setActiveId(blank.id);
    const fresh = newSession(crypto.randomUUID(), new Date());
    setSessions((all) => [fresh, ...all]);
    setActiveId(fresh.id);
  };

  const remove = () => {
    if (!active || pending) return;
    const id = active.id;
    if (active.messages.length > 0) {
      saveDeleted(uid, [...loadDeleted(uid), id]);
      api.deleteChat(id).catch(() => undefined);
    }
    const rest = sessions.filter((s) => s.id !== id);
    const next =
      rest.length > 0 ? rest : [newSession(crypto.randomUUID(), new Date())];
    setSessions(next);
    setActiveId(next[0]?.id ?? "");
  };

  const send = () => {
    const question = draft.trim();
    if (!active || question === "" || pending || !online) return;
    const turnNumber = Math.floor(active.turns.length / 2) + 1;
    const key = chatKey(
      uid,
      active.id,
      turnNumber,
      crypto.randomUUID().slice(0, 8),
    );
    setPending({
      sessionId: active.id,
      question,
      key,
      request: chatRequest(facts, active.turns, question, key),
    });
    setDraft("");
    setNotice("");
  };

  const onKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key !== "Enter" || e.shiftKey || e.nativeEvent.isComposing) return;
    e.preventDefault();
    send();
  };

  if (training) {
    return (
      <div className="chat">
        <h1>AI chat</h1>
        <p className="notice-soft">
          The AI chat is off while training, because it sends requests to the
          team database.
        </p>
      </div>
    );
  }

  const delivery = active && deliveryOf(`assistantChats/${active.id}`);
  const showing = pending && pending.sessionId === active?.id ? pending : null;
  return (
    <div className="chat">
      <header className="chat-head">
        <h1>AI chat</h1>
        {facts.eventKey === "" ? (
          <p className="notice-soft">
            No event is set, so the AI has no teams to talk about.{" "}
            <Link to="/settings?s=event">Open Settings</Link>
          </p>
        ) : (
          <p className="secondary">{`Answers use the ${facts.rows.length} teams and scouting for ${facts.eventKey}.`}</p>
        )}
        <p className="secondary">
          A local model on a team device writes the answers, and it can be
          wrong. Check numbers against the Teams page before you repeat them.
          Your saved chat is visible to you only.
        </p>
      </header>

      <div className="chat-bar">
        <label className="chat-pick">
          <span className="label">Chat</span>
          <select
            className="input"
            value={active?.id ?? ""}
            disabled={pending !== null}
            onChange={(e) => open(e.target.value)}
          >
            {sessions.map((s) => (
              <option key={s.id} value={s.id}>
                {displayTitle(s)}
              </option>
            ))}
          </select>
        </label>
        <div className="actions">
          <button
            type="button"
            className="btn"
            disabled={pending !== null}
            onClick={startChat}
          >
            New chat
          </button>
          <button
            type="button"
            className="btn"
            disabled={pending !== null || !active || sessions.length === 0}
            onClick={remove}
          >
            Delete chat
          </button>
        </div>
      </div>

      <ol className="chat-log" aria-label="Conversation">
        {active?.messages.map((m, i) => (
          <li
            // biome-ignore lint/suspicious/noArrayIndexKey: a transcript only grows
            key={i}
            className="chat-msg"
            data-kind={m.kind}
          >
            <span className="label">{m.kind === "user" ? "You" : "AI"}</span>
            <p className="chat-text">{m.text}</p>
            {m.kind === "assistant" && (
              <p className="secondary">
                {`Written by ${m.model ?? "an unknown model"}${m.at ? `, ${ago(Date.parse(m.at), Date.now())}` : ""}.`}
              </p>
            )}
          </li>
        ))}
        {showing && (
          <ChatTurn
            key={showing.key}
            transport={relay}
            request={showing.request}
            question={showing.question}
            online={online}
            onAnswer={answered}
            onCancel={cancel}
          />
        )}
      </ol>
      {active && active.messages.length === 0 && !showing && (
        <p className="secondary">
          Ask about a team, for example "How is team 1111 scoring?" or "Who
          should we watch in our next match?"
        </p>
      )}

      {!online && (
        <p className="notice-soft" role="status">
          You are offline. Saved chats still open, but a new question needs a
          connection.
        </p>
      )}
      {syncFailed && (
        <p className="notice-soft" role="status">
          Chats from your other devices could not load. Chats on this device
          still open.
        </p>
      )}
      {notice !== "" && (
        <p className="notice" role="status">
          {notice}
        </p>
      )}
      {delivery && (
        <p className="secondary">
          Chat saved: <DeliveryLine delivery={delivery} signedIn={signedIn} />
        </p>
      )}

      <form
        className="chat-form"
        onSubmit={(e) => {
          e.preventDefault();
          send();
        }}
      >
        <label className="label" htmlFor="chat-question">
          Your question
        </label>
        <textarea
          id="chat-question"
          className="input"
          rows={3}
          maxLength={maxQuestionChars}
          value={draft}
          disabled={pending !== null}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={onKeyDown}
        />
        <p className="secondary">Enter sends. Shift+Enter adds a new line.</p>
        <div className="actions">
          <button
            type="submit"
            className="btn primary"
            disabled={draft.trim() === "" || pending !== null || !online}
          >
            Send
          </button>
        </div>
      </form>
    </div>
  );
}
