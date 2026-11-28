import { PhotoThumb } from "./PhotoThumb";
import "./photos.css";

export function PhotoGallery({ keys }: { keys: readonly string[] }) {
  if (keys.length === 0) return null;
  return (
    <ul className="plain photo-grid" aria-label="Robot photos">
      {keys.map((key, i) => (
        <li key={key} className="photo-tile">
          <PhotoThumb source={{ key }} label={`photo ${i + 1}`} />
        </li>
      ))}
    </ul>
  );
}
