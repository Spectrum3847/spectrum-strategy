import { useEffect, useRef, useState } from "react";
import { decodeFrame } from "./decoder";

export type CameraState =
  | "starting"
  | "scanning"
  | "denied"
  | "missing"
  | "error";

export interface CameraProps {
  onCode(text: string): void;
}

const messages: Record<Exclude<CameraState, "scanning">, string> = {
  starting: "Starting the camera. Allow camera access if the browser asks.",
  denied:
    "Camera access is blocked. Allow the camera for this site in the browser settings, then try again.",
  missing:
    "No camera is available. A camera needs a device that has one and a secure (https) page.",
  error: "The camera or the QR reader could not start.",
};

function stateOf(error: unknown): CameraState {
  const name = error instanceof DOMException ? error.name : "";
  if (name === "NotAllowedError" || name === "SecurityError") return "denied";
  if (name === "NotFoundError" || name === "OverconstrainedError") {
    return "missing";
  }
  return "error";
}

const frameMs = 120;
const maxWidth = 1280;

export function ScanCamera({ onCode }: CameraProps) {
  const [attempt, setAttempt] = useState(0);
  return (
    <CameraFeed
      key={attempt}
      onCode={onCode}
      onRetry={() => setAttempt((n) => n + 1)}
    />
  );
}

function CameraFeed({
  onCode,
  onRetry,
}: CameraProps & { onRetry: () => void }) {
  const video = useRef<HTMLVideoElement>(null);
  const [state, setState] = useState<CameraState>("starting");
  const latest = useRef(onCode);
  latest.current = onCode;

  useEffect(() => {
    let stopped = false;
    let stream: MediaStream | null = null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    setState("starting");

    async function run() {
      if (!navigator.mediaDevices?.getUserMedia) {
        setState("missing");
        return;
      }
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: {
            facingMode: { ideal: "environment" },
            width: { ideal: 1280 },
            height: { ideal: 720 },
          },
          audio: false,
        });
      } catch (error) {
        if (!stopped) setState(stateOf(error));
        return;
      }
      const el = video.current;
      if (stopped || !el) {
        for (const track of stream.getTracks()) track.stop();
        return;
      }
      el.srcObject = stream;
      try {
        await el.play?.();
      } catch {
        if (!stopped) setState("error");
        return;
      }
      if (stopped) return;
      setState("scanning");

      const canvas = document.createElement("canvas");
      const ctx = canvas.getContext("2d", { willReadFrequently: true });
      const tick = async () => {
        if (stopped) return;
        if (ctx && el.readyState >= 2 && el.videoWidth > 0) {
          const scale = Math.min(1, maxWidth / el.videoWidth);
          canvas.width = Math.round(el.videoWidth * scale);
          canvas.height = Math.round(el.videoHeight * scale);
          ctx.drawImage(el, 0, 0, canvas.width, canvas.height);
          try {
            const text = await decodeFrame(
              ctx.getImageData(0, 0, canvas.width, canvas.height),
            );
            if (text !== null && !stopped) latest.current(text);
          } catch {
            if (!stopped) setState("error");
            return;
          }
        }
        if (!stopped) timer = setTimeout(() => void tick(), frameMs);
      };
      void tick();
    }
    void run();

    return () => {
      stopped = true;
      clearTimeout(timer);
      if (stream) for (const track of stream.getTracks()) track.stop();
      if (video.current) video.current.srcObject = null;
    };
  }, []);

  return (
    <div className="camera" data-state={state}>
      <video ref={video} playsInline muted aria-label="Camera view" />
      {state !== "scanning" && (
        <div className="camera-msg" role="status">
          <p>{messages[state]}</p>
          {state !== "starting" && (
            <button type="button" className="btn primary" onClick={onRetry}>
              Try again
            </button>
          )}
        </div>
      )}
    </div>
  );
}
