function applyAcceptedTrades(rotations, trades) {

  const out = rotations.map((r) => ({ ...r, shifts: [...r.shifts] }));
  const accepted = (trades || []).filter((t) => t.status === 'accepted');

  for (const trade of accepted) {
    swapBlock(out, trade.requesterUid, trade.targetUid, trade.requesterBlock);
    if (trade.targetBlock) {
      swapBlock(out, trade.targetUid, trade.requesterUid, trade.targetBlock);
    }
  }
  return out;
}

const sameBlock = (a, b) => a.startMatch === b.startMatch && a.endMatch === b.endMatch;

function swapBlock(rotations, fromUid, toUid, block) {
  if (!fromUid || !toUid || !block) return;
  const from = rotations.find((r) => r.uid === fromUid);
  const to = rotations.find((r) => r.uid === toUid);
  if (!from || !to) return;

  const given = from.shifts.find((s) => sameBlock(s, block));
  if (!given) return;
  from.shifts = from.shifts.filter((s) => !sameBlock(s, block));

  to.shifts = [
    ...to.shifts,
    { startMatch: block.startMatch, endMatch: block.endMatch, ...(given.station ? { station: given.station } : {}) },
  ];
}

export { applyAcceptedTrades };
