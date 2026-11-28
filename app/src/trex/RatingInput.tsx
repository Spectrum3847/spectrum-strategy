import { useId } from "react";
import { limits } from "./document";

const scale = Array.from(
  { length: limits.ratingMax - limits.ratingMin + 1 },
  (_, i) => limits.ratingMin + i,
);

export function RatingInput({
  value,
  onChange,
}: {
  value: number | null;
  onChange(rating: number): void;
}) {
  const name = useId();
  const ends = `${name}-ends`;
  return (
    <fieldset className="rating" aria-describedby={ends}>
      <legend className="field-name">Rating of this trait</legend>
      <div className="rating-row">
        {scale.map((n) => (
          <label key={n} className="rating-option">
            <input
              type="radio"
              name={name}
              value={n}
              checked={value === n}
              onChange={() => onChange(n)}
            />
            <span>{n}</span>
          </label>
        ))}
      </div>
      <p id={ends} className="rating-ends secondary">
        <span>1 is poor</span>
        <span>5 is excellent</span>
      </p>
    </fieldset>
  );
}
