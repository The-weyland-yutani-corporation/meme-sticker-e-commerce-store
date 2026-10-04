const baseUrl = `http://127.0.0.1:${process.env.PORT ?? "8080"}`;
const expectedSha = process.env.RELEASE_SHA;
const probeToken = process.env.SYNTHETIC_PROBE_TOKEN;

if (!expectedSha || !probeToken) {
  throw new Error("Startup verification requires RELEASE_SHA and SYNTHETIC_PROBE_TOKEN");
}

let health;
for (let attempt = 1; attempt <= 24; attempt += 1) {
  try {
    const response = await fetch(`${baseUrl}/api/health`);
    if (response.ok) {
      health = await response.json();
      break;
    }
  } catch {
    // The server may still be starting.
  }
  await new Promise((resolve) => setTimeout(resolve, 5000));
}

if (
  health?.status !== "ok" ||
  health?.service !== "meme-sticker-store" ||
  health?.version !== expectedSha
) {
  throw new Error("Startup health verification failed");
}

const syntheticResponse = await fetch(`${baseUrl}/api/internal/synthetic-order`, {
  method: "POST",
  headers: {
    authorization: `Bearer ${probeToken}`,
  },
});
const synthetic = await syntheticResponse.json();

if (
  !syntheticResponse.ok ||
  synthetic?.status !== "ok" ||
  synthetic?.deleted !== true ||
  typeof synthetic?.amountTotal !== "number" ||
  synthetic.amountTotal <= 0
) {
  throw new Error("Startup synthetic-order verification failed");
}

console.info("startup_verification.passed", {
  releaseSha: expectedSha,
});
