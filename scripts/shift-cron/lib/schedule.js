'use strict';

function applyAcceptedTrades(rotations, trades) {
  const byUid = new Map(rotations.map((r) => [r.uid, { ...r, shifts: [...r.shifts] }]));
  const accepted = (trades || []).filter((t) => t.status === 'accepted');

  for (const trade of accepted) {
    swapBlock(byUid, trade.requesterUid, trade.targetUid, trade.requesterBlock);
    if (trade.targetBlock) {
      swapBlock(byUid, trade.targetUid, trade.requesterUid, trade.targetBlock);
    }
  }
  return [...byUid.values()];
}

function swapBlock(byUid, fromUid, toUid, block) {
  const from = byUid.get(fromUid);
  if (from) {
    from.shifts = from.shifts.filter(
      (s) => !(s.startMatch === block.startMatch && s.endMatch === block.endMatch),
    );
  }
  const to = byUid.get(toUid);
  if (to) {
    to.shifts = [...to.shifts, block];
  }
}

module.exports = { applyAcceptedTrades };
