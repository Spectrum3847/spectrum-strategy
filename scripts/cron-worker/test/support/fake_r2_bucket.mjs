function createFakeR2Bucket(seed = {}, { failGet = () => false, failPut = () => false } = {}) {
  const store = new Map(Object.entries(seed));
  const calls = [];

  function wrap(value) {
    const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
    return {
      async arrayBuffer() {
        return bytes.buffer ?? bytes;
      },
      async text() {
        return typeof value === 'string' ? value : new TextDecoder().decode(value);
      },
      async json() {
        return JSON.parse(typeof value === 'string' ? value : new TextDecoder().decode(value));
      },
    };
  }

  async function get(key) {
    calls.push({ op: 'get', key });
    if (failGet(key)) throw new Error(`fake R2 get failure: ${key}`);
    return store.has(key) ? wrap(store.get(key)) : null;
  }

  async function put(key, value) {
    calls.push({ op: 'put', key });
    if (failPut(key)) throw new Error(`fake R2 put failure: ${key}`);
    store.set(key, value);
  }

  async function del(keyOrKeys) {
    const keys = Array.isArray(keyOrKeys) ? keyOrKeys : [keyOrKeys];
    calls.push({ op: 'delete', keys });
    for (const key of keys) store.delete(key);
  }

  async function list({ prefix = '', cursor } = {}) {
    calls.push({ op: 'list', prefix, cursor });
    const keys = [...store.keys()].filter((key) => key.startsWith(prefix)).sort();
    return { objects: keys.map((key) => ({ key })), truncated: false, cursor: null };
  }

  return { get, put, delete: del, list, store, calls };
}

export { createFakeR2Bucket };
