import { useMemo, useState } from "react";
import { Link } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { dismissItem } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { InlineForm, reasonError } from "../picks/parts";
import {
  applyLayout,
  type Layout,
  layoutOf,
  markDnp,
  maxDnp,
  maxTeams,
  placeTeam,
  refusalNote,
  removeTeam,
  tierOf,
} from "../picks/pickList";
import { sentMs } from "../picks/sentStamp";
import {
  pickListPath,
  savePickList,
  usePickLists,
} from "../picks/usePickLists";
import { DeliveryLine } from "../scout/ScoutForm";
import { pickStatus } from "./pickStatus";
import "../picks/picks.css";

export function PickControl({ team }: { team: number }) {
  const signedIn = useAuth().status === "signed-in";
  const roles = useRoles();
  const canEdit = roles.status === "ready" && isLead(roles.roles);
  const lists = usePickLists();
  const outbox = useOutbox();
  const [open, setOpen] = useState(false);
  const [listId, setListId] = useState<string | null>(null);
  const [tier, setTier] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  const sorted = useMemo(
    () => [...lists.items].sort((a, b) => b.updatedMs - a.updatedMs),
    [lists.items],
  );
  const list = sorted.find((l) => l.id === listId) ?? sorted[0] ?? null;

  if (!list) {
    return (
      <p className="secondary" role="status">
        {lists.ready ? (
          <>
            No pick lists yet.{" "}
            {canEdit && <Link to="/picks">Create one on Picks.</Link>}
          </>
        ) : (
          "Loading pick lists."
        )}
      </p>
    );
  }

  const layout = layoutOf(list);
  const current = tierOf(layout, team);
  const dnp = layout.dnp.find((d) => d.team === team);
  const placed = current !== null || dnp !== undefined;
  const chosen = Math.min(tier ?? current ?? 0, layout.tiers.length - 1);
  const item = outbox.find((i) => i.path === pickListPath(list.id));

  const change = async (next: Layout, full: string) => {
    if (next === layout) {
      setError(full);
      return;
    }
    setError(null);
    try {
      await savePickList(
        applyLayout(list, next, Date.now()),
        `Pick list ${list.name}`,
      );
    } catch (e) {
      console.error("Pick list save failed", e);
      setError("Could not save this change on this device. Try again.");
    }
  };

  return (
    <div className="team-pick">
      <p className="team-pick-line" role="status">
        <span>{pickStatus(list, team)}</span>
        {canEdit && (
          <button
            type="button"
            className="btn"
            aria-expanded={open}
            disabled={!signedIn}
            onClick={() => setOpen(!open)}
          >
            {open ? "Close" : "Pick list"}
          </button>
        )}
      </p>
      {item?.status === "refused" && (
        <p className="notice" role="alert">
          {refusalNote(sentMs(item), list.updatedMs)}{" "}
          <button
            type="button"
            className="btn"
            onClick={() => dismissItem(item.id)}
          >
            Discard my change
          </button>
        </p>
      )}
      {item && item.status !== "refused" && (
        <p className="secondary" role="status">
          <DeliveryLine
            delivery={{ status: item.status }}
            signedIn={signedIn}
          />
        </p>
      )}
      {error && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
      {canEdit && open && (
        <div className="team-pick-panel">
          {sorted.length > 1 && (
            <label className="pick-field">
              <span className="label">List</span>
              <select
                className="input"
                value={list.id}
                onChange={(e) => {
                  setListId(e.target.value);
                  setTier(null);
                  setError(null);
                }}
              >
                {sorted.map((l) => (
                  <option key={l.id} value={l.id}>
                    {l.name}
                  </option>
                ))}
              </select>
            </label>
          )}
          <form
            className="pick-form"
            onSubmit={(e) => {
              e.preventDefault();
              void change(
                placeTeam(layout, team, chosen),
                `This list already holds ${maxTeams} teams.`,
              );
            }}
          >
            <label className="pick-field">
              <span className="label">Tier</span>
              <select
                className="input"
                value={chosen}
                onChange={(e) => setTier(Number(e.target.value))}
              >
                {layout.tiers.map((t, i) => (
                  // biome-ignore lint/suspicious/noArrayIndexKey: tiers have no id
                  <option key={i} value={i}>
                    {t.name}
                  </option>
                ))}
              </select>
            </label>
            <button type="submit" className="btn">
              {current === null ? "Add to list" : "Move to tier"}
            </button>
          </form>
          <InlineForm
            key={`${list.id}-${dnp?.reason ?? ""}`}
            fields={[
              {
                label: "Reason to not pick",
                ...(dnp ? { initial: dnp.reason } : {}),
                max: 200,
              },
            ]}
            submit="Do not pick"
            validate={([text]) => reasonError(text ?? "")}
            onSubmit={([text]) =>
              void change(
                markDnp(layout, team, text ?? ""),
                `The do-not-pick list already holds ${maxDnp} teams.`,
              )
            }
          />
          {placed && (
            <div className="actions">
              <button
                type="button"
                className="btn"
                onClick={() => void change(removeTeam(layout, team), "")}
              >
                Remove from {list.name}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
