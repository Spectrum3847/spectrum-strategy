import { openableUrl, youtubeEmbedUrl } from "./video";

export function FilmPane({ url }: { url: string }) {
  const link = url.trim();
  if (link === "") return null;
  const embed = youtubeEmbedUrl(link);
  if (embed) {
    return (
      <div className="film">
        <iframe
          title="Match video"
          src={embed}
          allow="encrypted-media; picture-in-picture; fullscreen"
          allowFullScreen
          referrerPolicy="strict-origin-when-cross-origin"
          sandbox="allow-scripts allow-same-origin allow-presentation allow-popups"
          loading="lazy"
        />
      </div>
    );
  }
  const open = openableUrl(link);
  return (
    <p className="notice-soft">
      {open ? (
        <>
          This link is not a YouTube video, so it cannot play here.{" "}
          <a href={open} target="_blank" rel="noopener noreferrer">
            Open the video in a new tab
          </a>
        </>
      ) : (
        "The video link is not a web address that can be opened."
      )}
    </p>
  );
}
