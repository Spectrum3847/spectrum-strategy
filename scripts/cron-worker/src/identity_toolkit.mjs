const IDENTITY_TOOLKIT_BASE = 'https://identitytoolkit.googleapis.com/v1';

const REQUEST_TIMEOUT_MS = 10_000;

class IdentityToolkitError extends Error {
  constructor(message, { status, code } = {}) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

async function signInWithCustomToken(fetchImpl, apiKey, customToken) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), REQUEST_TIMEOUT_MS);
  let res;
  let data;
  try {
    res = await fetchImpl(
      `${IDENTITY_TOOLKIT_BASE}/accounts:signInWithCustomToken?key=${encodeURIComponent(apiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: customToken, returnSecureToken: true }),
        signal: ctl.signal,
      },
    );

    data = await res.json().catch(() => ({}));
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) {
    throw new IdentityToolkitError(
      `Identity Toolkit signInWithCustomToken failed: HTTP ${res.status} ${JSON.stringify(data)}`,
      { status: res.status, code: data?.error?.message },
    );
  }
  return { idToken: data.idToken, localId: data.localId };
}

export { signInWithCustomToken, IdentityToolkitError };
