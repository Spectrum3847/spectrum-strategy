import { type FormEvent, type ReactNode, useId, useState } from "react";

function Svg({ children }: { children: ReactNode }) {
  return (
    <svg
      className="pick-icon"
      viewBox="0 0 24 24"
      width="24"
      height="24"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

export const GripIcon = () => (
  <Svg>
    <path d="M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01" />
  </Svg>
);
export const UpIcon = () => (
  <Svg>
    <path d="M6 15l6-6 6 6" />
  </Svg>
);
export const DownIcon = () => (
  <Svg>
    <path d="M6 9l6 6 6-6" />
  </Svg>
);
export const MoreIcon = () => (
  <Svg>
    <path d="M5 12h.01M12 12h.01M19 12h.01" />
  </Svg>
);

interface Field {
  label: string;
  initial?: string;
  digits?: boolean;
  max?: number;
}

export function InlineForm({
  fields,
  submit,
  validate,
  onSubmit,
}: {
  fields: Field[];
  submit: string;
  validate?(values: string[]): string | null;
  onSubmit(values: string[]): void;
}) {
  const id = useId();
  const [values, setValues] = useState(fields.map((f) => f.initial ?? ""));
  const [error, setError] = useState<string | null>(null);

  const send = (e: FormEvent) => {
    e.preventDefault();
    const trimmed = values.map((v) => v.trim());
    const problem = validate?.(trimmed) ?? null;
    setError(problem);
    if (problem !== null) return;
    onSubmit(trimmed);
    setValues(
      fields.map((f, i) => (f.initial === undefined ? "" : (trimmed[i] ?? ""))),
    );
  };

  return (
    <form className="pick-form" onSubmit={send} noValidate>
      {fields.map((f, i) => (
        <label className="pick-field" key={f.label}>
          <span className="label">{f.label}</span>
          <input
            className="input"
            value={values[i]}
            maxLength={f.max}
            inputMode={f.digits ? "numeric" : undefined}
            aria-describedby={error ? `${id}-err` : undefined}
            aria-invalid={error ? true : undefined}
            onChange={(e) =>
              setValues(
                values.map((v, at) =>
                  at === i
                    ? f.digits
                      ? e.target.value.replace(/\D/g, "")
                      : e.target.value
                    : v,
                ),
              )
            }
          />
        </label>
      ))}
      <button type="submit" className="btn">
        {submit}
      </button>
      {error && (
        <p className="pick-error" id={`${id}-err`} role="alert">
          {error}
        </p>
      )}
    </form>
  );
}

export function teamError(text: string, known: number[]): string | null {
  const team = Number(text);
  if (!Number.isInteger(team) || team < 1 || team > 99999) {
    return "Enter a team number, like 3847.";
  }
  if (known.length > 0 && !known.includes(team)) {
    return `Team ${team} is not at this event.`;
  }
  return null;
}

export const reasonError = (text: string) =>
  text === "" ? "Say why, so the drive team trusts it." : null;
