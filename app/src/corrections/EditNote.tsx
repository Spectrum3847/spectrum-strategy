import { when } from "../team/Sections";
import type { EditInfo } from "./history";

export function EditNote({
  edit,
  className,
}: {
  edit: EditInfo;
  className: string;
}) {
  const time = edit.atMs > 0 ? when(new Date(edit.atMs).toISOString()) : "";
  const line = ["Edited", edit.by !== "" ? `by ${edit.by}` : "", time]
    .filter((p) => p !== "")
    .join(" ");
  return <span className={className}>{line}</span>;
}
