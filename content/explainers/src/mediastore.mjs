// The project's media bucket (Cloudflare R2, the same one the API serves from), for files the
// renderer must keep forever, such as paid AI images. Same settings as the backend:
// R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET.
// Requests are signed with AWS Signature V4, which R2 accepts, so no SDK is needed.
import { createHash, createHmac } from "node:crypto";

const sha256 = (data) => createHash("sha256").update(data).digest("hex");
const hmac = (key, data) => createHmac("sha256", key).update(data).digest();

/** The SigV4 Authorization header for a request (headers: lower-case names, values as sent). */
export function authorization({ method, url, headers, payloadHash, accessKey, secretKey, region, service = "s3", amzDate }) {
  const u = new URL(url);
  const all = { host: u.host, ...headers };
  const names = Object.keys(all).map((k) => k.toLowerCase()).sort();
  const lower = Object.fromEntries(Object.entries(all).map(([k, v]) => [k.toLowerCase(), String(v).trim()]));
  const query = [...u.searchParams].map(([k, v]) => [encodeURIComponent(k), encodeURIComponent(v)]).sort().map(([k, v]) => `${k}=${v}`).join("&");
  const canonical = [method, u.pathname || "/", query, names.map((k) => `${k}:${lower[k]}\n`).join(""), names.join(";"), payloadHash].join("\n");
  const day = amzDate.slice(0, 8);
  const scope = `${day}/${region}/${service}/aws4_request`;
  const toSign = ["AWS4-HMAC-SHA256", amzDate, scope, sha256(canonical)].join("\n");
  let key = hmac(`AWS4${secretKey}`, day);
  for (const part of [region, service, "aws4_request"]) key = hmac(key, part);
  return `AWS4-HMAC-SHA256 Credential=${accessKey}/${scope}, SignedHeaders=${names.join(";")}, Signature=${createHmac("sha256", key).update(toSign).digest("hex")}`;
}

/** The bucket, or null when the R2 settings are not all present. */
export function r2FromEnv({ env = process.env, fetch = globalThis.fetch, now = () => new Date() } = {}) {
  const { R2_ACCOUNT_ID: account, R2_ACCESS_KEY_ID: accessKey, R2_SECRET_ACCESS_KEY: secretKey, R2_BUCKET: bucket } = env;
  if (!account || !accessKey || !secretKey || !bucket) return null;
  const endpoint = `https://${account}.r2.cloudflarestorage.com/${encodeURIComponent(bucket)}`;

  async function send(method, key, body) {
    const url = `${endpoint}/${key.split("/").map(encodeURIComponent).join("/")}`;
    const payloadHash = sha256(body || "");
    const amzDate = now().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
    const headers = { "x-amz-content-sha256": payloadHash, "x-amz-date": amzDate, ...(body ? { "content-type": "image/png" } : {}) };
    headers.authorization = authorization({ method, url, headers, payloadHash, accessKey, secretKey, region: "auto", amzDate });
    return fetch(url, { method, headers, body });
  }

  return {
    name: `r2:${bucket}`,
    /** The object's bytes, or null if it isn't there. */
    async get(key) {
      const res = await send("GET", key);
      if (res.status === 404) return null;
      if (!res.ok) throw new Error(`R2 GET ${key}: ${res.status} ${(await res.text()).slice(0, 200)}`);
      return Buffer.from(await res.arrayBuffer());
    },
    async put(key, body) {
      const res = await send("PUT", key, body);
      if (!res.ok) throw new Error(`R2 PUT ${key}: ${res.status} ${(await res.text()).slice(0, 200)}`);
    },
  };
}
