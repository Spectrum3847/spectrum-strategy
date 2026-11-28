import { useTour } from "./tourContext";

export function TourPanel() {
  const tour = useTour();
  if (!tour) return null;
  return (
    <section className="panel" aria-labelledby="tour-h">
      <h2 id="tour-h">Welcome tour</h2>
      <p className="secondary">A short walk through the screens you can use.</p>
      <button type="button" className="btn" onClick={tour.open}>
        Show the tour
      </button>
    </section>
  );
}
