import { useRef, useState } from "react";
import { PhotoThumb } from "./PhotoThumb";
import { maxPhotos } from "./resize";
import { type Slot, slotText, waitingText } from "./state";
import type { EntryPhotos } from "./useEntryPhotos";
import "./photos.css";

function PhotoTile({
  slot,
  index,
  photos,
}: {
  slot: Slot;
  index: number;
  photos: EntryPhotos;
}) {
  const [confirming, setConfirming] = useState(false);
  const label = `photo ${index + 1}`;
  const item = slot.item;
  const source = item ? { blob: item.blob } : { key: slot.key ?? "" };
  return (
    <li className="photo-tile">
      <PhotoThumb source={source} label={label} />
      <p className="photo-state" data-state={item?.state ?? "uploaded"}>
        {slotText(item)}
      </p>
      {item?.state === "failed" && (
        <button
          type="button"
          className="btn"
          onClick={() => photos.retry(item.id)}
        >
          Retry upload
        </button>
      )}
      {confirming ? (
        <fieldset className="photo-confirm" aria-label={`Remove ${label}`}>
          <legend className="secondary">Remove this photo?</legend>
          <div className="actions">
            <button
              type="button"
              className="btn"
              onClick={() => photos.remove(slot)}
            >
              Remove
            </button>
            <button
              type="button"
              className="btn"
              onClick={() => setConfirming(false)}
            >
              Keep
            </button>
          </div>
        </fieldset>
      ) : (
        <button
          type="button"
          className="btn"
          aria-label={`Remove ${label}`}
          onClick={() => setConfirming(true)}
        >
          Remove
        </button>
      )}
    </li>
  );
}

export function PhotoSaveNote({ photos }: { photos: EntryPhotos }) {
  const items = photos.slots.flatMap((s) => (s.item ? [s.item] : []));
  const failed = items.filter((i) => i.state === "failed").length;
  const pending = items.filter(
    (i) => i.state === "waiting" || i.state === "uploading",
  ).length;
  if (failed + pending === 0) return null;
  const photoWord = (n: number) => (n === 1 ? "1 photo" : `${n} photos`);
  return (
    <p className="secondary" role="status">
      {pending > 0 &&
        `${photoWord(pending)} still to upload. It goes up in the background while this app is open and online. `}
      {failed > 0 &&
        `${photoWord(failed)} failed to upload. Open this entry to retry.`}
    </p>
  );
}

export function PhotoStrip({
  photos,
  blocked,
}: {
  photos: EntryPhotos;
  blocked?: string;
}) {
  const camera = useRef<HTMLInputElement>(null);
  const files = useRef<HTMLInputElement>(null);
  const disabled = !photos.canAdd || photos.busy || Boolean(blocked);

  function picked(input: HTMLInputElement) {
    const chosen = [...(input.files ?? [])];
    input.value = "";
    if (chosen.length > 0) void photos.add(chosen);
  }

  return (
    <section className="photo-strip" aria-labelledby="pit-photos">
      <h2 id="pit-photos" className="form-section">
        Photos
      </h2>
      <p className="secondary">
        {blocked ??
          `Up to ${maxPhotos} photos of the robot, ${photos.slots.length} added. Photos upload when there is a connection.`}
      </p>
      {photos.waiting && photos.slots.length > 0 && (
        <p className="notice-soft" role="status">
          {waitingText}
        </p>
      )}
      {photos.slots.length > 0 && (
        <ul className="plain photo-grid">
          {photos.slots.map((slot, i) => (
            <PhotoTile key={slot.id} slot={slot} index={i} photos={photos} />
          ))}
        </ul>
      )}
      <div className="actions">
        <button
          type="button"
          className="btn"
          disabled={disabled}
          onClick={() => camera.current?.click()}
        >
          Take photo
        </button>
        <button
          type="button"
          className="btn"
          disabled={disabled}
          onClick={() => files.current?.click()}
        >
          Choose photo
        </button>
        <input
          ref={camera}
          type="file"
          accept="image/*"
          capture="environment"
          hidden
          onChange={(event) => picked(event.currentTarget)}
        />
        <input
          ref={files}
          type="file"
          accept="image/*"
          multiple
          hidden
          onChange={(event) => picked(event.currentTarget)}
        />
      </div>
      {photos.busy && (
        <p className="secondary" role="status">
          Preparing the photo.
        </p>
      )}
      {photos.notice && (
        <p className="notice" role="alert">
          {photos.notice}
        </p>
      )}
    </section>
  );
}
