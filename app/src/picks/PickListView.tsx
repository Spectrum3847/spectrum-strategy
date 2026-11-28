import {
  type KeyboardEvent,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { Link } from "react-router";
import { compareHref } from "../teams/compare";
import { Columns, type Editing } from "./Columns";
import { type Drop, useRowDrag } from "./drag";
import { type TeamFacts, tiedWithAbove } from "./facts";
import { InlineForm } from "./parts";
import {
  type Layout,
  layoutOf,
  markDnp,
  maxDnp,
  maxTeams,
  moveBy,
  type PickList,
  placeTeam,
  rankedCount,
  removeTeam,
  tierOf,
} from "./pickList";
import { DnpSection, PoolSection } from "./Sections";

export function PickListView({
  list,
  facts,
  nicknames,
  eventTeams,
  taken,
  us,
  onLayout,
  onRename,
}: {
  list: PickList;
  facts: Map<number, TeamFacts>;
  nicknames: Map<number, string>;
  eventTeams: number[];
  taken: Map<number, string>;
  us: number | null;
  onLayout(layout: Layout): void;
  onRename(name: string): void;
}) {
  const layout = useMemo(() => layoutOf(list), [list]);
  const [chosen, setChosen] = useState<number[]>([]);
  const [notice, setNotice] = useState<string | null>(null);
  const [renaming, setRenaming] = useState(false);
  const refocus = useRef<number | null>(null);

  useEffect(() => {
    if (refocus.current === null) return;
    document
      .querySelector<HTMLElement>(`[data-handle="${refocus.current}"]`)
      ?.focus();
    refocus.current = null;
  });

  const change = (next: Layout) => {
    if (next === layout) {
      if (rankedCount(layout) >= maxTeams) {
        setNotice(
          `A pick list holds ${maxTeams} ranked teams. Remove one first.`,
        );
      } else if (layout.dnp.length >= maxDnp) {
        setNotice(`Do not pick holds ${maxDnp} teams. Remove one first.`);
      }
      return;
    }
    setNotice(null);
    onLayout(next);
  };

  const move = (team: number, delta: -1 | 1) => {
    refocus.current = team;
    change(moveBy(layout, team, delta));
  };

  const drop = (team: number, to: Drop) => {
    if (to.kind === "pool") change(removeTeam(layout, team));
    else change(placeTeam(layout, team, to.tier, to.index));
  };
  const drag = useRowDrag(drop);

  const onHandleKey = (ev: KeyboardEvent, team: number) => {
    const tier = tierOf(layout, team);
    if (ev.key === "ArrowUp" || ev.key === "ArrowDown") {
      ev.preventDefault();
      move(team, ev.key === "ArrowUp" ? -1 : 1);
    } else if (
      (ev.key === "ArrowLeft" || ev.key === "ArrowRight") &&
      tier !== null
    ) {
      ev.preventDefault();
      const to = tier + (ev.key === "ArrowLeft" ? -1 : 1);
      const target = layout.tiers[to];
      if (!target) return;
      const at = layout.tiers[tier]?.teams.indexOf(team) ?? 0;
      refocus.current = team;
      change(placeTeam(layout, team, to, Math.min(at, target.teams.length)));
    }
  };

  const ranked = new Set(layout.tiers.flatMap((t) => t.teams));
  const listed = new Set(layout.dnp.map((d) => d.team));
  const pool = eventTeams.filter((t) => !ranked.has(t) && !listed.has(t));

  const tiedWith = useMemo(
    () =>
      tiedWithAbove(
        layout.tiers.flatMap((t) => t.teams),
        facts,
      ),
    [layout, facts],
  );

  const editing: Editing = {
    layout,
    facts,
    tiedWith,
    taken,
    known: eventTeams,
    drag,
    change,
    move,
    onHandleKey,
    chosen,
    toggleCompare: (team) =>
      setChosen((current) =>
        current.includes(team)
          ? current.filter((t) => t !== team)
          : current.length < 3
            ? [...current, team]
            : current,
      ),
    markDnp: (team, reason) => change(markDnp(layout, team, reason)),
    notify: setNotice,
  };

  return (
    <div className="pick-list">
      <div className="pick-list-head">
        <h2>{list.name}</h2>
        <button
          type="button"
          className="btn"
          aria-expanded={renaming}
          onClick={() => setRenaming(!renaming)}
        >
          Rename list
        </button>
      </div>
      <div className="actions">
        <p className="secondary">
          Tick 2 or 3 teams to compare. {chosen.join(", ")}
        </p>
        {chosen.length >= 2 ? (
          <Link className="btn" to={compareHref(chosen)}>
            Compare
          </Link>
        ) : (
          <button className="btn" disabled type="button">
            Compare
          </button>
        )}
      </div>
      {renaming && (
        <InlineForm
          fields={[{ label: "List name", initial: list.name, max: 128 }]}
          submit="Save name"
          validate={([name]) => (name === "" ? "Give the list a name." : null)}
          onSubmit={([name]) => {
            onRename(name ?? "");
            setRenaming(false);
          }}
        />
      )}
      {notice && (
        <p className="notice" role="status">
          {notice}
        </p>
      )}
      <p className="sr-only" id="pick-keys">
        Arrow up and down move this team. Arrow left and right move it to the
        neighboring tier.
      </p>
      <Columns e={editing} total={rankedCount(layout)} />
      <DnpSection e={editing} us={us} />
      <PoolSection teams={pool} nicknames={nicknames} e={editing} />
    </div>
  );
}
