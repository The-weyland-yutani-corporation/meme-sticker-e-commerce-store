import {
  createPublicKey,
  verify,
  type JsonWebKey as CryptoJsonWebKey,
} from "node:crypto";

const issuer = "https://token.actions.githubusercontent.com";
const audience = "meme-forge-synthetic-order";
const repository =
  "The-weyland-yutani-corporation/meme-sticker-e-commerce-store";
const subject = `repo:${repository}:environment:production`;

type JsonObject = Record<string, unknown>;

type SigningJsonWebKey = CryptoJsonWebKey & {
  kid?: string;
  kty?: string;
  use?: string;
};

type JsonWebKeySet = {
  keys: SigningJsonWebKey[];
};

let cachedJwks: JsonWebKeySet | undefined;
let cachedJwksExpiresAt = 0;

function decodeSegment(segment: string): JsonObject {
  return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
}

function hasAudience(value: unknown) {
  return value === audience || (Array.isArray(value) && value.includes(audience));
}

export function verifyGitHubActionsOidcToken(
  token: string,
  jwks: JsonWebKeySet,
  now = Date.now(),
) {
  if (token.length > 8192) {
    return false;
  }

  const segments = token.split(".");
  if (segments.length !== 3) {
    return false;
  }

  try {
    const [encodedHeader, encodedPayload, encodedSignature] = segments;
    const header = decodeSegment(encodedHeader);
    const claims = decodeSegment(encodedPayload);
    if (
      header.alg !== "RS256" ||
      typeof header.kid !== "string" ||
      claims.iss !== issuer ||
      !hasAudience(claims.aud) ||
      claims.repository !== repository ||
      claims.sub !== subject ||
      typeof claims.exp !== "number" ||
      typeof claims.nbf !== "number"
    ) {
      return false;
    }

    const nowSeconds = Math.floor(now / 1000);
    if (claims.exp <= nowSeconds || claims.nbf > nowSeconds + 30) {
      return false;
    }

    const jwk = jwks.keys.find(
      (candidate) =>
        candidate.kid === header.kid &&
        candidate.kty === "RSA" &&
        candidate.use === "sig",
    );
    if (!jwk) {
      return false;
    }

    return verify(
      "RSA-SHA256",
      Buffer.from(`${encodedHeader}.${encodedPayload}`),
      createPublicKey({ format: "jwk", key: jwk }),
      Buffer.from(encodedSignature, "base64url"),
    );
  } catch {
    return false;
  }
}

export async function isTrustedGitHubActionsToken(token: string) {
  if (token.split(".").length !== 3) {
    return false;
  }

  try {
    if (!cachedJwks || cachedJwksExpiresAt <= Date.now()) {
      const response = await fetch(`${issuer}/.well-known/jwks`, {
        cache: "no-store",
      });
      if (!response.ok) {
        console.error("github_oidc.jwks_unavailable", {
          status: response.status,
        });
        return false;
      }
      cachedJwks = (await response.json()) as JsonWebKeySet;
      cachedJwksExpiresAt = Date.now() + 60 * 60 * 1000;
    }

    return verifyGitHubActionsOidcToken(token, cachedJwks);
  } catch (error) {
    console.error("github_oidc.verification_failed", error);
    return false;
  }
}
