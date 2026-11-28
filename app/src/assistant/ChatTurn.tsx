import { useEffect, useState } from "react";
import { chatMinimumChars } from "./chat";
import {
  type AiSummary,
  type AssistantRequest,
  looksLikeAnAnswer,
} from "./queue";
import type { RelayChat } from "./relay";

interface Props {
  transport: RelayChat;
  request: AssistantRequest;
  question: string;
  onAnswer(summary: AiSummary): void;
  onCancel(): void;
  online: boolean;
}
export function ChatTurn({
  transport,
  request,
  question,
  onAnswer,
  onCancel,
  online,
}: Props) {
  const [status, setStatus] = useState("Connecting to a relay.");
  const [text, setText] = useState("");
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (!online) {
      setStatus(
        "You are offline. The question is sent again when you reconnect.",
      );
      setFailed(false);
      return;
    }
    let live = true;
    let answer = "";
    setFailed(false);
    setText("");
    setStatus("Connecting to a relay.");
    transport.ask(request, (event) => {
      if (!live) return;
      if (event.type === "connecting") setStatus("Connecting to a relay.");
      if (event.type === "waiting") setStatus("Waiting for an answer.");
      if (event.type === "chunk") {
        answer += event.text;
        setText(answer);
        setStatus("Receiving answer.");
      }
      if (event.type === "error") {
        setStatus(event.message);
        setFailed(true);
      }
      if (event.type === "done") {
        if (!looksLikeAnAnswer(answer, chatMinimumChars)) {
          setStatus("The relay did not return an answer. Try again.");
          setFailed(true);
          return;
        }
        onAnswer({
          text: answer.trim(),
          model: event.model,
          coverage: null,
          generatedAtMs: Date.now(),
        });
      }
    });
    return () => {
      live = false;
      transport.cancel();
    };
  }, [transport, request, onAnswer, online]);
  return (
    <li className="chat-msg" data-kind="user">
      <span className="label">You</span>
      <p className="chat-text">{question}</p>
      {text && (
        <>
          <span className="label">AI</span>
          <p className="chat-text">{text}</p>
        </>
      )}
      <p className={failed ? "notice" : "secondary"} role="status">
        {status}
      </p>
      <div className="actions">
        <button type="button" className="btn" onClick={onCancel}>
          {failed ? "Edit question" : "Cancel"}
        </button>
      </div>
    </li>
  );
}
