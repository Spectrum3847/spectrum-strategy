import { lazy, Suspense, useEffect, useState } from "react";
import { Link, useParams } from "react-router";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { useTbaEvent } from "../data/useTbaEvent";
import { bundled } from "./field";
import { boardTitle, isPracticeBoard, localSessions } from "./list";
import { idKey, listLocal } from "./local";
import { boardSides, type Session } from "./model";
import { useRemoteBoardById } from "./remote";
import "./board.css";

const Board = lazy(() =>
  import("./PlanTab").then((m) => ({ default: m.Board })),
);

interface Found {
  session: Session;
  key: string;
}

export function BoardRoute() {
  const { id = "" } = useParams();
  const tba = useTbaEvent();
  const roles = useRoles();
  const remote = useRemoteBoardById(id);
  const [local, setLocal] = useState<Found | null | undefined>(undefined);

  useEffect(() => {
    let live = true;
    setLocal(undefined);
    listLocal().then(
      (all) => {
        if (live) {
          setLocal(
            localSessions(all, bundled.latest).find(
              (s) => s.session.id === id,
            ) ?? null,
          );
        }
      },
      () => live && setLocal(null),
    );
    return () => {
      live = false;
    };
  }, [id]);

  const session = local?.session ?? remote.board;
  const back = (
    <Link to="/boards" className="btn">
      All boards
    </Link>
  );

  if (!session) {
    const looking = local === undefined || !remote.ready;
    return (
      <div className="boards">
        <h1>Board</h1>
        {back}
        <p className={looking ? "secondary" : "notice"} role="status">
          {looking
            ? "Loading the board."
            : "This board is not on this device or in the database. It may have been deleted."}
        </p>
      </div>
    );
  }

  const scheduled = tba.matches.find(
    (m) =>
      session.eventKey !== "" &&
      m.key.toLowerCase() ===
        `${session.eventKey}_qm${session.matchNumber}`.toLowerCase(),
  );
  const ours = session.alliance === "Blue" ? "blue" : "red";
  const { red, blue } = scheduled ?? boardSides(session);
  const practice = isPracticeBoard({
    session,
    scheduled: scheduled !== undefined,
    scheduleKnown:
      session.eventKey === "" ||
      (tba.eventKey === session.eventKey &&
        (tba.status === "ready" || tba.matches.length > 0)),
  });
  const title = boardTitle(session);

  return (
    <div className="boards">
      <header className="boards-head">
        <h1>{title}</h1>
        {back}
      </header>
      <Suspense
        fallback={
          <p className="secondary" role="status">
            Loading the board
          </p>
        }
      >
        <Board
          id={id}
          localKey={local?.key ?? idKey(id)}
          eventKey={session.eventKey}
          matchNumber={session.matchNumber}
          red={red}
          blue={blue}
          ours={ours}
          label={title}
          practice={practice}
          canMoveSides={roles.status === "ready" && isLead(roles.roles)}
        />
      </Suspense>
    </div>
  );
}
