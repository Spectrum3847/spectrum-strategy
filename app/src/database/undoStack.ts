export interface Edit {
  entryId: string;
  field: string;
  before: unknown;
  after: unknown;
}

export const undoLimit = 50;

export const pushEdit = (stack: Edit[], edit: Edit): Edit[] =>
  [...stack, edit].slice(-undoLimit);

export function popEdit(stack: Edit[]): [Edit | null, Edit[]] {
  const last = stack.at(-1);
  return last ? [last, stack.slice(0, -1)] : [null, stack];
}
