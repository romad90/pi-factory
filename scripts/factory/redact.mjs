// Secret redaction (D97, D101): one function for every text the factory keeps
// outside the project (the run archive, the guard's refusal log). It works on
// raw text and on JSON-escaped text (a transcript line, a logged tool input),
// where quotes arrive as \" and newlines as \n.
//
// It is a pattern list, not a proof: a secret with no known shape and no
// telling name around it goes through. What it catches:
//   private key blocks; AWS access keys; GitHub (ghp_, gho_, ghu_, ghs_, ghr_,
//   github_pat_), GitLab (glpat-) and Slack (xoxb-, xoxp-, …) tokens; OpenAI
//   and Anthropic style keys (sk-, sk-proj-, sk-ant-); Bearer tokens; JWTs;
//   credentials in URLs (scheme://user:pass@host); and assignments to a name
//   containing password, passwd, secret, token or api_key/apikey, quoted or
//   not (export DB_PASSWORD=x, "token": "x", api_key: x).
// A count is not a secret (D150): a name ending in "tokens" (totalTokens,
// max_tokens, cacheReadTokens) with a number keeps its number, or every
// assistant line of a transcript stops being JSON.
export const REDACTED = "[REDACTED]";

const TOKENS = new RegExp([
  "-----BEGIN ([A-Z]+ )?PRIVATE KEY-----[\\s\\S]*?-----END ([A-Z]+ )?PRIVATE KEY-----",
  "-----BEGIN ([A-Z]+ )?PRIVATE KEY-----",
  "\\b(AKIA|ASIA)[0-9A-Z]{16}\\b",
  "\\bgh[pousr]_[A-Za-z0-9]{20,}",
  "\\bgithub_pat_[A-Za-z0-9_]{20,}",
  "\\bglpat-[A-Za-z0-9_-]{20,}",
  "\\bxox[abposr]-[A-Za-z0-9-]{10,}",
  "\\bsk-(?:proj-|ant-(?:[a-z]+\\d*-)?)?[A-Za-z0-9_-]{16,}",
  "\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}",
].join("|"), "g");

// Bearer <token>: keep the word, drop the token.
const BEARER = /\b(Bearer)\s+[A-Za-z0-9._~+/=-]{8,}/gi;
// scheme://user:password@host: keep the scheme and user.
const URL_CRED = /\b([a-z][a-z0-9+.-]*:\/\/[^\s/:@"'\\]+):[^@\s/"'\\]+@/gi;
// name = value, name: value, "name": "value", \"name\": \"value\".
// The name contains a telling word; the value is what follows, quoted or not.
// A value starting with $, < or { is a reference or placeholder, not a secret.
const ASSIGN = /\b([A-Za-z0-9_.-]*(?:password|passwd|secret|token|api_?key|apikey)[A-Za-z0-9_]*)((?:\\*["'])?\s*[:=]\s*(?:\\*["'])?)(?![$<{\s]|\[REDACTED\])([^\s"'\\,;}&)]+)/gi;

export function redact(text) {
  if (typeof text !== "string" || !text) return text;
  return text
    .replace(TOKENS, REDACTED)
    .replace(BEARER, `$1 ${REDACTED}`)
    .replace(URL_CRED, `$1:${REDACTED}@`)
    .replace(ASSIGN, (m, name, sep, value) => (value === REDACTED || COUNT.test(name) && /^\d+(\.\d+)?$/.test(value) ? m : `${name}${sep}${REDACTED}`));
}
const COUNT = /tokens$/i;

// One transcript or log line as JSON, or null. A line archived before D150 may
// hold a bare [REDACTED] where a number was ("totalTokens":[REDACTED]): it
// reads as null, and the rest of the line is kept.
export function parseRecord(line) {
  if (typeof line !== "string" || !line.trim()) return null;
  try { return JSON.parse(line); } catch {}
  if (!line.includes(REDACTED)) return null;
  try { return JSON.parse(line.replace(/(:\s*)\[REDACTED\](?=\s*[,}\]])/g, "$1null")); } catch { return null; }
}
