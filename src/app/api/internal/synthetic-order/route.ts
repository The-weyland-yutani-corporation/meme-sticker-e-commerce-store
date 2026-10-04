import { createHash, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import {
  createPaymentFreeOrder,
  verifyAndDeleteSyntheticOrder,
} from "@/application/orders";
import { isTrustedGitHubActionsToken } from "@/security/github-oidc";

function tokenMatches(received: string, expected: string) {
  const receivedHash = createHash("sha256").update(received).digest();
  const expectedHash = createHash("sha256").update(expected).digest();
  return timingSafeEqual(receivedHash, expectedHash);
}

export async function POST(request: Request) {
  const expectedToken = process.env.SYNTHETIC_PROBE_TOKEN;
  const authorization = request.headers.get("authorization") ?? "";
  const receivedToken = authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length)
    : "";
  const keyVaultTokenMatches =
    Boolean(expectedToken) && tokenMatches(receivedToken, expectedToken ?? "");
  if (
    !keyVaultTokenMatches &&
    !(await isTrustedGitHubActionsToken(receivedToken))
  ) {
    return NextResponse.json({ error: "Unauthorized." }, { status: 401 });
  }

  try {
    const order = await createPaymentFreeOrder(
      [{ slug: "this-is-fine", quantity: 1 }],
      { synthetic: true },
    );
    if (!order) {
      throw new Error("Synthetic catalog item is unavailable");
    }

    const verifiedOrder = await verifyAndDeleteSyntheticOrder(order.id);
    console.info("synthetic_order.verified", {
      amountTotal: verifiedOrder.amountTotal,
      orderId: verifiedOrder.id,
    });

    return NextResponse.json({
      amountTotal: verifiedOrder.amountTotal,
      deleted: true,
      status: "ok",
    });
  } catch (error) {
    console.error("synthetic_order.failed", error);
    return NextResponse.json(
      { error: "Synthetic order verification failed." },
      { status: 503 },
    );
  }
}
