import { type FormEvent, useState } from "react";
import { dismissItem, type OutboxItem } from "../outbox/outbox";
import { DeliveryState } from "../shifts/MyShifts";
import { mergeSections, type Section, totalTeams } from "./assignments";
import {
  addColumn,
  addItem,
  addItems,
  type Kind,
  moveColumn,
  moveItem,
  parsePasted,
  removeColumn,
  removeItem,
  renameColumn,
  renameItem,
  tablePath,
} from "./edit";
import type { useTableEdits } from "./useTableEdits";

type Edits = ReturnType<typeof useTableEdits>;

function Field({
  label,
  value,
  onCommit,
  placeholder,
}: {
  label: string;
  value: string;
  onCommit(value: string): void;
  placeholder?: string;
}) {
  return (
    <input
      key={value}
      className="input"
      aria-label={label}
      defaultValue={value}
      placeholder={placeholder}
      onBlur={(e) => {
        const next = e.currentTarget.value.trim();
        if (next === "") e.currentTarget.value = value;
        else if (next !== value) onCommit(next);
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter") e.currentTarget.blur();
      }}
    />
  );
}

function AddRow({
  label,
  onAdd,
  onPaste,
}: {
  label: string;
  onAdd(text: string): void;
  onPaste(items: string[]): void;
}) {
  const [text, setText] = useState("");
  const [pasting, setPasting] = useState(false);

  function submit(e: FormEvent) {
    e.preventDefault();
    if (pasting) onPaste(parsePasted(text));
    else onAdd(text);
    setText("");
    setPasting(false);
  }

  return (
    <form className="trex-add" onSubmit={submit}>
      {pasting ? (
        <textarea
          className="input"
          aria-label={`Paste ${label}s`}
          rows={4}
          value={text}
          onChange={(e) => setText(e.target.value)}
        />
      ) : (
        <input
          className="input"
          aria-label={`New ${label}`}
          value={text}
          onChange={(e) => setText(e.target.value)}
        />
      )}
      <button type="submit" className="btn primary">
        {pasting ? "Add all" : "Add"}
      </button>
      <button
        type="button"
        className="btn"
        onClick={() => {
          setPasting(!pasting);
          setText("");
        }}
      >
        {pasting ? "One at a time" : "Paste a list"}
      </button>
    </form>
  );
}

function ItemList({
  label,
  items,
  onRename,
  onMove,
  onRemove,
  onAdd,
  onPaste,
}: {
  label: string;
  items: string[];
  onRename(i: number, text: string): void;
  onMove(i: number, delta: -1 | 1): void;
  onRemove(i: number): void;
  onAdd(text: string): void;
  onPaste(items: string[]): void;
}) {
  return (
    <>
      {items.length === 0 ? (
        <p className="secondary">None yet</p>
      ) : (
        <ul className="plain trex-rows">
          {items.map((item, i) => (
            // biome-ignore lint/suspicious/noArrayIndexKey: entries repeat and are edited by position
            <li key={i} className="trex-row">
              <Field
                label={`${label} ${i + 1}`}
                value={item}
                onCommit={(text) => onRename(i, text)}
              />
              <button
                type="button"
                className="btn trex-icon"
                aria-label={`Move ${label} ${i + 1} up`}
                disabled={i === 0}
                onClick={() => onMove(i, -1)}
              >
                {"↑"}
              </button>
              <button
                type="button"
                className="btn trex-icon"
                aria-label={`Move ${label} ${i + 1} down`}
                disabled={i === items.length - 1}
                onClick={() => onMove(i, 1)}
              >
                {"↓"}
              </button>
              <button
                type="button"
                className="btn trex-icon"
                aria-label={`Remove ${label} ${i + 1}`}
                onClick={() => onRemove(i)}
              >
                {"×"}
              </button>
            </li>
          ))}
        </ul>
      )}
      <AddRow label={label} onAdd={onAdd} onPaste={onPaste} />
    </>
  );
}

function SectionEditor({
  section,
  canUp,
  canDown,
  edits,
}: {
  section: Section;
  canUp: boolean;
  canDown: boolean;
  edits: Edits;
}) {
  const [removing, setRemoving] = useState(false);
  const { assignmentKey: a, teamKey: t } = section;

  const rename = (name: string) => {
    if (a) void edits.save("assignments", (c) => renameColumn(c, a, name));
    if (t) void edits.save("teamList", (c) => renameColumn(c, t, name));
  };
  const remove = () => {
    if (a) void edits.save("assignments", (c) => removeColumn(c, a));
    if (t) void edits.save("teamList", (c) => removeColumn(c, t));
  };

  return (
    <li className="trex-assign trex-edit">
      <div className="trex-edit-head">
        <Field label="Trait name" value={section.name} onCommit={rename} />
        {a && (
          <>
            <button
              type="button"
              className="btn trex-icon"
              aria-label={`Move ${section.name} up`}
              disabled={!canUp}
              onClick={() =>
                void edits.save("assignments", (c) => moveColumn(c, a, -1))
              }
            >
              {"↑"}
            </button>
            <button
              type="button"
              className="btn trex-icon"
              aria-label={`Move ${section.name} down`}
              disabled={!canDown}
              onClick={() =>
                void edits.save("assignments", (c) => moveColumn(c, a, 1))
              }
            >
              {"↓"}
            </button>
          </>
        )}
      </div>

      <h4>Scouters</h4>
      {a ? (
        <ItemList
          label="Scouter"
          items={section.scouters}
          onRename={(i, text) =>
            void edits.save("assignments", (c) => renameItem(c, a, i, text))
          }
          onMove={(i, d) =>
            void edits.save("assignments", (c) => moveItem(c, a, i, d))
          }
          onRemove={(i) =>
            void edits.save("assignments", (c) => removeItem(c, a, i))
          }
          onAdd={(text) =>
            void edits.save("assignments", (c) => addItem(c, a, text))
          }
          onPaste={(items) =>
            void edits.save("assignments", (c) => addItems(c, a, items))
          }
        />
      ) : (
        <button
          type="button"
          className="btn"
          onClick={() =>
            void edits.save("assignments", (c) =>
              addColumn(c, crypto.randomUUID(), section.name),
            )
          }
        >
          Add a scouter list
        </button>
      )}

      <h4>Teams</h4>
      {t ? (
        <ItemList
          label="Team"
          items={section.teams}
          onRename={(i, text) =>
            void edits.save("teamList", (c) => renameItem(c, t, i, text))
          }
          onMove={(i, d) =>
            void edits.save("teamList", (c) => moveItem(c, t, i, d))
          }
          onRemove={(i) =>
            void edits.save("teamList", (c) => removeItem(c, t, i))
          }
          onAdd={(text) =>
            void edits.save("teamList", (c) => addItem(c, t, text))
          }
          onPaste={(items) =>
            void edits.save("teamList", (c) => addItems(c, t, items))
          }
        />
      ) : (
        <button
          type="button"
          className="btn"
          onClick={() =>
            void edits.save("teamList", (c) =>
              addColumn(c, crypto.randomUUID(), section.name),
            )
          }
        >
          Add a team list
        </button>
      )}

      {removing ? (
        <div className="trex-confirm">
          <span className="trex-confirm-text">
            Remove this trait with its scouters and teams?
          </span>
          <button type="button" className="btn primary" onClick={remove}>
            Remove
          </button>
          <button
            type="button"
            className="btn"
            onClick={() => setRemoving(false)}
          >
            Keep it
          </button>
        </div>
      ) : (
        <button
          type="button"
          className="btn trex-remove"
          onClick={() => setRemoving(true)}
        >
          Remove trait
        </button>
      )}
    </li>
  );
}

const tableNames = { assignments: "Assignments", teamList: "Team list" };

function latestDelivery(outbox: OutboxItem[], kind: Kind) {
  const item = outbox
    .filter((i) => i.path === tablePath[kind])
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))[0];
  if (!item) return undefined;
  return {
    id: item.id,
    status: item.status,
    ...(item.error ? { error: item.error } : {}),
  };
}

export function TrexEditor({
  edits,
  outbox,
}: {
  edits: Edits;
  outbox: OutboxItem[];
}) {
  const [name, setName] = useState("");
  const sections = mergeSections(
    edits.assignments.columns,
    edits.teamList.columns,
  );

  function addTrait(e: FormEvent) {
    e.preventDefault();
    if (name.trim() === "") return;
    void edits.save("assignments", (c) =>
      addColumn(c, crypto.randomUUID(), name),
    );
    void edits.save("teamList", (c) => addColumn(c, crypto.randomUUID(), name));
    setName("");
  }

  return (
    <div className="trex-editor">
      {edits.error && (
        <p className="notice" role="alert">
          {edits.error}
        </p>
      )}
      <Field
        label="Team list title"
        value={edits.teamList.title}
        placeholder="Pit Scouting Team Assignments"
        onCommit={(title) => void edits.setTitle(title)}
      />
      {sections.length === 0 ? (
        <p className="secondary">
          No T-REx traits yet. Add one to start assigning scouters.
        </p>
      ) : (
        <ul className="plain trex-assigns">
          {sections.map((s, i) => (
            <SectionEditor
              key={`${s.assignmentKey}:${s.teamKey}`}
              section={s}
              canUp={i > 0}
              canDown={sections[i + 1]?.assignmentKey != null}
              edits={edits}
            />
          ))}
        </ul>
      )}
      <form className="trex-add" onSubmit={addTrait}>
        <input
          className="input"
          aria-label="New trait"
          placeholder="New trait, e.g. Defense"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <button type="submit" className="btn primary">
          Add trait
        </button>
      </form>
      <p className="secondary">
        {totalTeams(edits.teamList.columns) > 0 &&
          `Total teams: ${totalTeams(edits.teamList.columns)}. `}
        Each change is saved as you make it.
      </p>
      {(["assignments", "teamList"] as const).map((kind) => {
        const delivery = latestDelivery(outbox, kind);
        return (
          delivery && (
            <p key={kind} className="delivery">
              {tableNames[kind]}:{" "}
              <DeliveryState
                delivery={delivery}
                onDismiss={(id) => dismissItem(id)}
              />
            </p>
          )
        );
      })}
    </div>
  );
}
