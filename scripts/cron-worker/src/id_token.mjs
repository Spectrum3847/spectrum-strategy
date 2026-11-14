function bearerToken(header) {
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return null;
  return header.slice('Bearer '.length).trim() || null;
}

function claimedUid(token) {
  const payload = token.split('.')[1];
  if (!payload) return null;
  const base64 = payload.replaceAll('-', '+').replaceAll('_', '/');
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=');
  let sub;
  try {
    sub = JSON.parse(atob(padded)).sub;
  } catch {
    return null;
  }
  return typeof sub === 'string' && /^[A-Za-z0-9]{1,128}$/.test(sub) ? sub : null;
}

export { bearerToken, claimedUid };
