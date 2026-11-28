import { useId } from "react";
import { EditNote } from "../corrections/EditNote";
import { choiceOptions, type ScoutField } from "../scout/config";
import { cellKind, isReadOnly } from "./cellValue";
import { cellOf, type DbRow } from "./rows";
import type { Grid } from "./useGrid";

const focusOnMount = (el: HTMLElement | null) => el?.focus();

function Input({
  field,
  grid,
  errorId,
}: {
  field: ScoutField;
  grid: Grid;
  errorId: string;
}) {
  const o = grid.open;
  if (!o) return null;
  const label = field.title.trim() || field.code;
  const common = {
    "aria-label": label,
    "aria-invalid": o.error !== "" || undefined,
    "aria-describedby": o.error !== "" ? errorId : undefined,
  };
  const kind = cellKind(field);
  if (kind === "select") {
    return (
      <select
        {...common}
        className="input db-cell-input"
        ref={focusOnMount}
        value={o.draft}
        onChange={(e) => grid.update({ draft: e.target.value })}
      >
        <option value="">Blank</option>
        {choiceOptions(field, [o.draft]).map(([key, text]) => (
          <option key={key} value={key}>
            {text}
          </option>
        ))}
      </select>
    );
  }
  if (kind === "multi") {
    return (
      <fieldset className="db-cell-picks">
        <legend className="sr-only">{label}</legend>
        {choiceOptions(field, o.picks).map(([key, text], i) => (
          <label key={key} className="db-cell-pick">
            <input
              type="checkbox"
              ref={i === 0 ? focusOnMount : undefined}
              checked={o.picks.includes(key)}
              onChange={(e) =>
                grid.update({
                  picks: e.target.checked
                    ? [...o.picks, key]
                    : o.picks.filter((p) => p !== key),
                })
              }
            />
            {text}
          </label>
        ))}
      </fieldset>
    );
  }
  if (kind === "longText") {
    return (
      <textarea
        {...common}
        className="input db-cell-input"
        ref={focusOnMount}
        rows={3}
        value={o.draft}
        onChange={(e) => grid.update({ draft: e.target.value })}
      />
    );
  }
  return (
    <input
      {...common}
      className="input db-cell-input"
      ref={focusOnMount}
      type="text"
      inputMode={kind === "text" ? "text" : "decimal"}
      autoComplete="off"
      value={o.draft}
      onChange={(e) => grid.update({ draft: e.target.value })}
    />
  );
}

export function DbCell({
  field,
  row,
  grid,
  r,
  c,
}: {
  field: ScoutField;
  row: DbRow;
  grid: Grid;
  r: number;
  c: number;
}) {
  const errorId = useId();
  const cell = cellOf(field, row);
  const content = (
    <>
      {cell.text}
      {cell.edit !== null && <EditNote edit={cell.edit} className="db-was" />}
      {cell.was !== null && (
        <span className="db-was">{`Scout entered ${cell.was}`}</span>
      )}
    </>
  );
  if (!grid.enabled) {
    return (
      <td className="db-field" data-corrected={cell.was !== null || undefined}>
        {content}
      </td>
    );
  }
  const o = grid.open;
  const here = o !== null && o.id === row.id && o.code === field.code;
  const readOnly = isReadOnly(field);
  return (
    // biome-ignore lint/a11y/useAriaPropsSupportedByRole: a td in a role=grid table is a gridcell
    <td
      className="db-field db-gridcell"
      data-cell=""
      tabIndex={grid.isStop(r, c) ? 0 : -1}
      aria-readonly={readOnly || undefined}
      data-readonly={readOnly || undefined}
      data-open={here || undefined}
      data-corrected={cell.was !== null || undefined}
      onKeyDown={(e) => grid.onKeyDown(e, row, field)}
      onClick={() => grid.onClick(row, field)}
      onFocus={() => grid.onFocusCell(row, field)}
      onBlur={(e) => {
        if (here && !e.currentTarget.contains(e.relatedTarget)) {
          grid.finish("stay");
        }
      }}
    >
      {here && o ? (
        <div className="db-cell-edit">
          <Input field={field} grid={grid} errorId={errorId} />
          {o.error !== "" && (
            <span id={errorId} className="db-cell-error" role="alert">
              {o.error}
            </span>
          )}
        </div>
      ) : (
        content
      )}
    </td>
  );
}
