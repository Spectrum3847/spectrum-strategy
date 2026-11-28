import { Link } from "react-router";
import { minMatches } from "./predictionCheck";
import { usePredictionCheck } from "./usePredictionCheck";

export function PredictionLine() {
  const { checks, firstWithMatches } = usePredictionCheck();
  const check = checks[firstWithMatches];
  if (check.n === 0) return null;
  const text = check.enough
    ? `Predictions so far: the favourite won ${check.right} of ${check.n} (${Math.round((check.right / check.n) * 100)}%)${check.error !== null ? `, scores off by ${Math.round(check.error)} points on average` : ""}.`
    : `Predictions: too early to judge, ${check.n} played and ${minMatches} needed.`;
  return (
    <p className="secondary">
      {text} <Link to="/scout/accuracy/predictions">Prediction check</Link>
    </p>
  );
}
