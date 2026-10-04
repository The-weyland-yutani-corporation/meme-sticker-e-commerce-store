import { generateKeyPairSync, sign } from "node:crypto";
import { describe, expect, it } from "vitest";
import { verifyGitHubActionsOidcToken } from "@/security/github-oidc";

const now = Date.UTC(2026, 9, 4, 15, 0, 0);
const nowSeconds = Math.floor(now / 1000);
const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
});
const publicJwk = publicKey.export({ format: "jwk" });
publicJwk.kid = "test-key";
publicJwk.use = "sig";

function createToken(overrides: Record<string, unknown> = {}) {
  const header = Buffer.from(
    JSON.stringify({ alg: "RS256", kid: "test-key", typ: "JWT" }),
  ).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({
      aud: "meme-forge-synthetic-order",
      exp: nowSeconds + 300,
      iss: "https://token.actions.githubusercontent.com",
      nbf: nowSeconds - 30,
      repository:
        "The-weyland-yutani-corporation/meme-sticker-e-commerce-store",
      sub: "repo:The-weyland-yutani-corporation@264313301/meme-sticker-e-commerce-store@1385623955:environment:production",
      ...overrides,
    }),
  ).toString("base64url");
  const signingInput = `${header}.${payload}`;
  const signature = sign(
    "RSA-SHA256",
    Buffer.from(signingInput),
    privateKey,
  ).toString("base64url");
  return `${signingInput}.${signature}`;
}

describe("GitHub Actions OIDC verification", () => {
  it("accepts an exact production-environment token", () => {
    expect(
      verifyGitHubActionsOidcToken(
        createToken(),
        { keys: [publicJwk] },
        now,
      ),
    ).toBe(true);
  });

  it.each([
    ["repository", { repository: "attacker/repository" }],
    ["environment subject", { sub: "repo:attacker/repository:environment:production" }],
    ["audience", { aud: "different-audience" }],
    ["expiry", { exp: nowSeconds - 1 }],
  ])("rejects a token with the wrong %s", (_name, overrides) => {
    expect(
      verifyGitHubActionsOidcToken(
        createToken(overrides),
        { keys: [publicJwk] },
        now,
      ),
    ).toBe(false);
  });
});
