import { useState } from "react";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { type FormId, formIds, formName } from "./doc";
import { type Draft, FormEditor } from "./FormEditor";
import "./configEditor.css";

export function FormsPanel() {
  const roles = useRoles();
  const canEdit = roles.status === "ready" && isLead(roles.roles);
  const [form, setForm] = useState<FormId>("scout");
  const [drafts, setDrafts] = useState<Record<FormId, Draft | null>>({
    scout: null,
    pit: null,
    prescout: null,
  });
  return (
    <section className="panel" aria-labelledby="forms-h">
      <h2 id="forms-h">Team forms</h2>
      <p className="secondary">
        {canEdit
          ? "The scout, pit and prescout forms. A saved change reaches every signed-in device."
          : "The scout, pit and prescout forms your team uses."}
      </p>
      <div className="actions">
        {formIds.map((id) => (
          <button
            key={id}
            type="button"
            className={id === form ? "btn primary" : "btn"}
            aria-pressed={id === form}
            onClick={() => setForm(id)}
          >
            {formName[id]}
            {drafts[id] ? " (unsaved)" : ""}
          </button>
        ))}
      </div>
      <h3 className="ce-h3">{formName[form]}</h3>
      <FormEditor
        key={form}
        form={form}
        canEdit={canEdit}
        draft={drafts[form]}
        setDraft={(next) => setDrafts((d) => ({ ...d, [form]: next }))}
      />
    </section>
  );
}
