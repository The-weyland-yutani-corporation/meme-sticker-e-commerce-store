import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const policy = readFileSync(".factory/policy.yml", "utf8");
const attestation = readFileSync(
  ".github/workflows/factory-review-attestation.yml",
  "utf8",
);

describe("factory infrastructure authority", () => {
  it("reserves infrastructure changes for the governance lane", () => {
    expect(policy).toMatch(
      /governance:[\s\S]*?controlled_paths:[\s\S]*?-\s+"infra\/\*\*"/,
    );
    expect(policy).toMatch(
      /implementation:[\s\S]*?prohibited_paths:[\s\S]*?-\s+"infra\/\*\*"/,
    );
  });

  it("enforces governance review for infrastructure without the retired bypass", () => {
    expect(attestation).toContain("\\.factory/|\\.github/|infra/");
    expect(attestation).not.toContain("FACTORY_TOKENLESS_MIGRATION_SHA");
  });
});
