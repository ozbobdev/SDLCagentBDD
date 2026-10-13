"use strict";
// GitHub App client: installation tokens, comments, labels, and file commits on a branch + PR.
const https = require("https");
const crypto = require("crypto");

function request(method, path, token, body) {
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : null;
    const req = https.request(
      { host: "api.github.com", path, method, headers: { authorization: `Bearer ${token}`, accept: "application/vnd.github+json", "user-agent": "sdlc-orchestrator", "x-github-api-version": "2022-11-28", ...(payload ? { "content-type": "application/json", "content-length": Buffer.byteLength(payload) } : {}) } },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          const json = text ? JSON.parse(text) : {};
          if (res.statusCode >= 300) return reject(new Error(`GitHub ${method} ${path} -> ${res.statusCode}: ${json.message || text}`));
          resolve(json);
        });
      }
    );
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function appJwt(appId, privateKey) {
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({ iat: now - 60, exp: now + 540, iss: appId })}`;
  return `${unsigned}.${crypto.createSign("RSA-SHA256").update(unsigned).sign(privateKey, "base64url")}`;
}

function createGitHubClient({ appId, installationId, privateKey }) {
  let cached = { token: null, exp: 0 };
  const configured = !!(appId && installationId && privateKey && privateKey !== "unset");

  async function token() {
    if (cached.token && cached.exp > Date.now() + 60000) return cached.token;
    const res = await request("POST", `/app/installations/${installationId}/access_tokens`, appJwt(appId, privateKey), {});
    cached = { token: res.token, exp: Date.parse(res.expires_at) };
    return cached.token;
  }
  const call = async (method, path, body) => request(method, path, await token(), body);

  return {
    configured,
    comment: (repo, number, body) => call("POST", `/repos/${repo}/issues/${number}/comments`, { body }),
    addLabels: (repo, number, labels) => call("POST", `/repos/${repo}/issues/${number}/labels`, { labels }),
    removeLabel: (repo, number, label) => call("DELETE", `/repos/${repo}/issues/${number}/labels/${encodeURIComponent(label)}`).catch(() => {}),
    getIssue: (repo, number) => call("GET", `/repos/${repo}/issues/${number}`),
    // Branch from the default branch, commit files via the contents API, open a PR. Never pushes to the default branch.
    async openPullRequest(repo, { branch, title, body, files }) {
      const info = await call("GET", `/repos/${repo}`);
      const base = info.default_branch;
      const ref = await call("GET", `/repos/${repo}/git/ref/heads/${base}`);
      await call("POST", `/repos/${repo}/git/refs`, { ref: `refs/heads/${branch}`, sha: ref.object.sha });
      for (const f of files) {
        let sha;
        try { sha = (await call("GET", `/repos/${repo}/contents/${f.path}?ref=${branch}`)).sha; } catch { /* new file */ }
        await call("PUT", `/repos/${repo}/contents/${f.path}`, { message: f.message || `squad: update ${f.path}`, content: Buffer.from(f.content).toString("base64"), branch, sha });
      }
      return call("POST", `/repos/${repo}/pulls`, { title, body, head: branch, base });
    },
  };
}

module.exports = { createGitHubClient };
