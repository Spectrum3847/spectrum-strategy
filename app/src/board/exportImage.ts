import { strokeParts } from "./geometry";
import {
  type Label,
  type Marker,
  type Phase,
  phaseLabels,
  type Session,
  type Stroke,
} from "./model";

export const layoutWidth = 1000;
export const outputWidth = 1800;
const headerHeight = 56;
const legendHeight = 64;

const color = {
  page: "#f2ecf7",
  surface: "#eae1f1",
  ink: "#2f2538",
  muted: "#645870",
  hairline: "#c9bad8",
  accent: "#3c0060",
  grid: "#c2afd3",
  red: "#c02b2b",
  blue: "#1f4fa8",
  onAlliance: "#fdfcfe",
};
const fontFamily = "Overpass, system-ui, sans-serif";

export interface ImageLayout {
  scale: number;
  width: number;
  height: number;
  fieldHeight: number;
  legendTop: number;
  fieldTop: number;
}

export function imageLayout(aspect: number): ImageLayout {
  const safe = aspect > 0 ? aspect : 2;
  const fieldHeight = layoutWidth / safe;
  const scale = outputWidth / layoutWidth;
  return {
    scale,
    width: outputWidth,
    height: Math.round((headerHeight + legendHeight + fieldHeight) * scale),
    fieldHeight,
    legendTop: headerHeight,
    fieldTop: headerHeight + legendHeight,
  };
}

export function boardTitle(session: {
  eventName: string;
  matchNumber: number;
}): string {
  const name = session.eventName.trim();
  return name === ""
    ? `Match ${session.matchNumber}`
    : `${name} - Match ${session.matchNumber}`;
}

export function exportFileName(title: string, phase: Phase): string {
  const base = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "");
  return `${base === "" ? "strategy_match" : base}_${phase}.png`;
}

export function wrapLines(
  text: string,
  maxWidth: number,
  measure: (s: string) => number,
): string[] {
  const lines: string[] = [];
  let line = "";
  for (const word of text.split(/\s+/).filter(Boolean)) {
    const next = line === "" ? word : `${line} ${word}`;
    if (line !== "" && measure(next) > maxWidth) {
      lines.push(line);
      line = word;
    } else {
      line = next;
    }
  }
  if (line !== "") lines.push(line);
  return lines;
}

const numbers = (s: string): number[] =>
  (s.match(/-?\d+(?:\.\d+)?/g) ?? []).map(Number);

function tracePoints(ctx: Ctx, flat: number[]) {
  ctx.beginPath();
  for (let i = 0; i + 1 < flat.length; i += 2) {
    const x = flat[i] as number;
    const y = flat[i + 1] as number;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
}

export type Ctx = Pick<
  CanvasRenderingContext2D,
  | "save"
  | "restore"
  | "scale"
  | "translate"
  | "beginPath"
  | "moveTo"
  | "lineTo"
  | "closePath"
  | "arc"
  | "rect"
  | "fill"
  | "stroke"
  | "fillRect"
  | "strokeRect"
  | "fillText"
  | "measureText"
  | "drawImage"
  | "clip"
> & {
  fillStyle: CanvasRenderingContext2D["fillStyle"];
  strokeStyle: CanvasRenderingContext2D["strokeStyle"];
  lineWidth: number;
  lineCap: CanvasLineCap;
  lineJoin: CanvasLineJoin;
  globalAlpha: number;
  font: string;
  textAlign: CanvasTextAlign;
  textBaseline: CanvasTextBaseline;
};

export interface BoardPicture {
  title: string;
  phase: Phase;
  aspect: number;
  strokes: Stroke[];
  markers: Marker[];
  labels: Label[];
  sideOf: (m: Marker) => "red" | "blue";
}

export function pictureOf(
  session: Session,
  phase: Phase,
  aspect: number,
  sideOf: BoardPicture["sideOf"],
): BoardPicture {
  return {
    title: boardTitle(session),
    phase,
    aspect,
    strokes: session.strokes[phase],
    markers: session.markers[phase],
    labels: session.labels[phase],
    sideOf,
  };
}

function box(ctx: Ctx, x: number, y: number, w: number, h: number) {
  ctx.beginPath();
  ctx.rect(x, y, w, h);
}

function drawHeader(ctx: Ctx, pic: BoardPicture) {
  ctx.fillStyle = color.page;
  ctx.fillRect(0, 0, layoutWidth, headerHeight);
  ctx.textBaseline = "middle";
  ctx.fillStyle = color.ink;
  ctx.font = `700 24px ${fontFamily}`;
  ctx.textAlign = "left";
  ctx.fillText(pic.title, 16, headerHeight / 2, layoutWidth - 200);
  ctx.fillStyle = color.accent;
  ctx.textAlign = "right";
  ctx.fillText(phaseLabels[pic.phase], layoutWidth - 16, headerHeight / 2);
}

function drawLegend(ctx: Ctx, pic: BoardPicture) {
  ctx.save();
  ctx.translate(0, headerHeight);
  ctx.fillStyle = color.surface;
  ctx.fillRect(0, 0, layoutWidth, legendHeight);
  ctx.strokeStyle = color.hairline;
  ctx.lineWidth = 1;
  box(ctx, 0.5, 0.5, layoutWidth - 1, legendHeight - 1);
  ctx.stroke();

  const slot = layoutWidth / 3;
  ctx.strokeStyle = color.muted;
  ctx.lineWidth = 2;
  ctx.lineJoin = "round";
  for (let i = 0; i < 3; i++) {
    const x = i * slot + 8;
    const y = (legendHeight - 24) / 2;
    ctx.beginPath();
    if (i === 0) {
      ctx.moveTo(x + 12, y + 5);
      ctx.lineTo(x + 20, y + 19);
      ctx.lineTo(x + 4, y + 19);
      ctx.closePath();
    } else if (i === 1) {
      ctx.arc(x + 12, y + 12, 8, 0, Math.PI * 2);
    } else {
      ctx.rect(x + 5, y + 5, 14, 14);
    }
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(x + 32, legendHeight - 12);
    ctx.lineTo((i + 1) * slot - 8, legendHeight - 12);
    ctx.stroke();
  }

  ctx.strokeStyle = color.ink;
  ctx.fillStyle = color.ink;
  ctx.lineWidth = 3;
  ctx.lineCap = "round";
  for (const s of pic.strokes) {
    if (!s.legend) continue;
    const first = s.points[0];
    if (!first) continue;
    if (s.points.length === 1) {
      ctx.beginPath();
      ctx.arc(
        first.x * layoutWidth,
        first.y * legendHeight,
        1.5,
        0,
        Math.PI * 2,
      );
      ctx.fill();
      continue;
    }
    tracePoints(
      ctx,
      s.points.flatMap((p) => [p.x * layoutWidth, p.y * legendHeight]),
    );
    ctx.stroke();
  }
  ctx.restore();
}

function drawField(
  ctx: Ctx,
  pic: BoardPicture,
  image: CanvasImageSource | null,
  fieldHeight: number,
) {
  ctx.save();
  ctx.translate(0, headerHeight + legendHeight);
  ctx.fillStyle = color.surface;
  ctx.fillRect(0, 0, layoutWidth, fieldHeight);
  if (image) ctx.drawImage(image, 0, 0, layoutWidth, fieldHeight);

  ctx.lineWidth = 1;
  for (const f of [0.25, 0.5, 0.75]) {
    ctx.strokeStyle = f === 0.5 ? color.accent : color.grid;
    ctx.globalAlpha = f === 0.5 ? 0.35 : 0.6;
    ctx.lineWidth = f === 0.5 ? 2 : 1;
    tracePoints(ctx, [layoutWidth * f, 0, layoutWidth * f, fieldHeight]);
    ctx.stroke();
    ctx.lineWidth = 1;
    ctx.strokeStyle = color.grid;
    ctx.globalAlpha = 0.6;
    tracePoints(ctx, [0, fieldHeight * f, layoutWidth, fieldHeight * f]);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;

  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  const size = { w: layoutWidth, h: fieldHeight };
  for (const s of pic.strokes) {
    if (s.legend) continue;
    const { bands, arrows } = strokeParts(s.points, s.color, size);
    ctx.lineWidth = 4;
    ctx.globalAlpha = 0.95;
    for (const band of bands) {
      ctx.strokeStyle = band.color;
      tracePoints(ctx, numbers(band.points));
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
    ctx.lineWidth = 2.5;
    for (const arrow of arrows) {
      ctx.strokeStyle = arrow.color;
      tracePoints(ctx, numbers(arrow.d));
      ctx.stroke();
    }
  }

  for (const label of pic.labels) drawLabel(ctx, label, fieldHeight);
  for (const m of pic.markers) drawMarker(ctx, m, pic.sideOf(m), fieldHeight);
  ctx.restore();
}

function drawLabel(ctx: Ctx, label: Label, fieldHeight: number) {
  ctx.font = `400 12px ${fontFamily}`;
  const measure = (s: string) => ctx.measureText(s).width;
  const lines = wrapLines(label.text, 264, measure);
  const textW = Math.max(0, ...lines.map(measure));
  const w = textW + 18;
  const h = Math.max(32, lines.length * 16 + 10);
  const x = label.x * layoutWidth - w / 2;
  const y = label.y * fieldHeight - h / 2;
  ctx.fillStyle = color.surface;
  box(ctx, x, y, w, h);
  ctx.fill();
  ctx.strokeStyle = color.hairline;
  ctx.lineWidth = 1;
  ctx.stroke();
  ctx.fillStyle = color.ink;
  ctx.textAlign = "left";
  ctx.textBaseline = "middle";
  const top = y + h / 2 - ((lines.length - 1) * 16) / 2;
  lines.forEach((line, i) => {
    ctx.fillText(line, x + 9, top + i * 16);
  });
}

function drawMarker(
  ctx: Ctx,
  m: Marker,
  side: "red" | "blue",
  fieldHeight: number,
) {
  const fill = side === "red" ? color.red : color.blue;
  ctx.font = `700 15px ${fontFamily}`;
  const text = m.team === null ? "?" : String(m.team);
  const w = Math.max(44, 18 + 4 + ctx.measureText(text).width + 20);
  const h = 32;
  const x = m.position.x * layoutWidth - w / 2;
  const y = m.position.y * fieldHeight - h / 2;
  ctx.fillStyle = fill;
  box(ctx, x, y, w, h);
  ctx.fill();
  ctx.strokeStyle = color.onAlliance;
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.fillStyle = color.onAlliance;
  box(ctx, x + 10, y + 7, 18, 18);
  ctx.fill();
  ctx.textBaseline = "middle";
  ctx.textAlign = "center";
  ctx.font = `700 12px ${fontFamily}`;
  ctx.fillStyle = fill;
  ctx.fillText(side === "red" ? "R" : "B", x + 19, y + 16.5);
  ctx.font = `700 15px ${fontFamily}`;
  ctx.fillStyle = color.onAlliance;
  ctx.textAlign = "left";
  ctx.fillText(text, x + 32, y + 16.5);
}

export function drawBoard(
  ctx: Ctx,
  pic: BoardPicture,
  image: CanvasImageSource | null,
): ImageLayout {
  const layout = imageLayout(pic.aspect);
  ctx.save();
  ctx.scale(layout.scale, layout.scale);
  ctx.fillStyle = color.page;
  ctx.fillRect(
    0,
    0,
    layoutWidth,
    headerHeight + legendHeight + layout.fieldHeight,
  );
  drawHeader(ctx, pic);
  drawLegend(ctx, pic);
  drawField(ctx, pic, image, layout.fieldHeight);
  ctx.restore();
  return layout;
}

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("Could not load the field image."));
    img.src = src;
  });
}

export async function renderBoardPng(
  pic: BoardPicture,
  imageSrc: string,
): Promise<Blob> {
  const image = await loadImage(imageSrc);
  try {
    await document.fonts?.load(`700 24px ${fontFamily}`);
  } catch {
  }
  const layout = imageLayout(pic.aspect);
  const canvas = document.createElement("canvas");
  canvas.width = layout.width;
  canvas.height = layout.height;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("This browser cannot draw the image.");
  drawBoard(ctx, pic, image);
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) =>
        blob ? resolve(blob) : reject(new Error("Could not encode the image.")),
      "image/png",
    );
  });
}

export type Delivery = "shared" | "downloaded" | "cancelled";

type Nav = Pick<Navigator, "canShare" | "share">;

export function download(blob: Blob, fileName: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  a.style.display = "none";
  document.body.append(a);
  a.click();
  setTimeout(() => {
    a.remove();
    URL.revokeObjectURL(url);
  }, 30_000);
}

export async function deliverImage(
  blob: Blob,
  fileName: string,
  title: string,
  nav: Partial<Nav> = navigator,
  save: (b: Blob, name: string) => void = download,
): Promise<Delivery> {
  const file = new File([blob], fileName, { type: "image/png" });
  if (nav.canShare?.({ files: [file] }) && nav.share) {
    try {
      await nav.share({ files: [file], title });
      return "shared";
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") {
        return "cancelled";
      }
    }
  }
  save(blob, fileName);
  return "downloaded";
}

export async function exportBoard(
  pic: BoardPicture,
  imageSrc: string,
): Promise<{ delivery: Delivery; fileName: string }> {
  const fileName = exportFileName(pic.title, pic.phase);
  const blob = await renderBoardPng(pic, imageSrc);
  return { delivery: await deliverImage(blob, fileName, pic.title), fileName };
}
