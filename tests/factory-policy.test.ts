import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const policy = readFileSync(".factory/policy.yml", "utf8");
const attestation = readFileSync(
  ".github/workflows/factory-review-attestation.yml",
  "utf8",
);
const bootstrap = readFileSync(
  "scripts/azure/bootstrap-production.ps1",
  "utf8",
);
const preflight = readFileSync(
  "scripts/azure/preflight-production.ps1",
  "utf8",
);
const parameters = readFileSync("infra/main.bicepparam", "utf8");
const bootstrapDocs = readFileSync("docs/factory-bootstrap.md", "utf8");

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

  it("keeps the governed Azure production region aligned", () => {
    expect(parameters).toContain("param location = 'centralus'");
    expect(bootstrap).toContain('[string]$Location = "centralus"');
    expect(bootstrapDocs).toContain("PostgreSQL Flexible Server in Central US");
    expect(bootstrapDocs).not.toContain("East US 2");
  });

  it("keeps production preflight cloud mutations disabled", () => {
    expect(preflight).toContain('"ready", "blocked", "already_configured"');
    expect(preflight).toContain('"deployment", "sub", "what-if"');
    expect(preflight).not.toMatch(
      /az\s+(group|identity)\s+create|az\s+role\s+assignment\s+create|az\s+deployment\s+\w+\s+create|az\s+consumption\s+budget\s+create|gh\s+variable\s+set/,
    );
  });
});
