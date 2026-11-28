import { SketchToggle } from "../board/Sketch";
import { emptySketch, strokesFromList } from "../board/sketch";
import type { TrexReport } from "../data/parse";

export function TrexDrawing({ report }: { report: TrexReport }) {
  if (!report.strokes) return null;
  const sketch = { ...emptySketch(), auton: strokesFromList(report.strokes) };
  return <SketchToggle surface="Trait drawing" value={sketch} phased={false} />;
}
