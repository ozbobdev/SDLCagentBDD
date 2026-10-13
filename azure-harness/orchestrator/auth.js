"use strict";
// Validates Entra ID app-only tokens (RS256) sent by the dispatch workflow.
const https = require("https");
const crypto = require("crypto");

let jwksCache = { at: 0, keys: [] };

function getJson(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); } catch (e) { reject(e); }
      });
    }).on("error", reject);
  });
}

async function getKeys(tenant) {
  if (Date.now() - jwksCache.at > 3600000) {
    const jwks = await getJson(`https://login.microsoftonline.com/${tenant}/discovery/v2.0/keys`);
    jwksCache = { at: Date.now(), keys: jwks.keys || [] };
  }
  return jwksCache.keys;
}

const b64 = (s) => Buffer.from(s, "base64url");

async function verifyToken(token, { tenant, audience, allowedClientIds, requiredRole, keys }) {
  const parts = (token || "").split(".");
  if (parts.length !== 3) throw new Error("malformed token");
  const header = JSON.parse(b64(parts[0]).toString());
  const claims = JSON.parse(b64(parts[1]).toString());
  if (header.alg !== "RS256") throw new Error("unsupported alg");

  const jwk = (keys || (await getKeys(tenant))).find((k) => k.kid === header.kid);
  if (!jwk) throw new Error("signing key not found");
  const ok = crypto.createVerify("RSA-SHA256").update(`${parts[0]}.${parts[1]}`).verify(crypto.createPublicKey({ key: jwk, format: "jwk" }), b64(parts[2]));
  if (!ok) throw new Error("bad signature");

  const now = Math.floor(Date.now() / 1000);
  if (claims.exp && claims.exp < now) throw new Error("token expired");
  if (claims.nbf && claims.nbf > now + 60) throw new Error("token not yet valid");
  if (claims.tid !== tenant) throw new Error("wrong tenant");
  if (claims.aud !== audience) throw new Error("wrong audience");
  const caller = claims.appid || claims.azp;
  if (!caller || !allowedClientIds.includes(caller)) throw new Error("caller not allowed");
  if (requiredRole && !(claims.roles || []).includes(requiredRole)) throw new Error("missing app role");
  return claims;
}

module.exports = { verifyToken };
