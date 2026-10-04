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
const infrastructure = readFileSync("infra/main.bicep", "utf8");
const releaseWorkflow = readFileSync(
  ".github/workflows/release-health.yml",
  "utf8",
);
const packageApp = readFileSync("scripts/release/package-app.sh", "utf8");
const startProduction = readFileSync(
  "scripts/release/start-production.sh",
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

  it("keeps production data services private and App Service VNet integrated", () => {
    expect(infrastructure).toContain(
      "resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets",
    );
    expect(infrastructure).toContain("virtualNetworkSubnetId: appSubnet.id");
    expect(infrastructure).toContain("vnetRouteAllEnabled: true");
    expect(infrastructure.match(/publicNetworkAccess: 'Disabled'/g)).toHaveLength(
      3,
    );
    expect(infrastructure).toContain(
      "resource postgresPrivateEndpoint 'Microsoft.Network/privateEndpoints",
    );
    expect(infrastructure).toContain(
      "resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints",
    );
    expect(infrastructure).toContain(
      "resource blobPrivateEndpoint 'Microsoft.Network/privateEndpoints",
    );
  });

  it("keeps runner releases off private Azure data planes", () => {
    expect(releaseWorkflow).toContain("actions/upload-artifact@");
    expect(releaseWorkflow).toContain('gh run download "$PREVIOUS_RUN_ID"');
    expect(releaseWorkflow).not.toContain("az storage blob");
    expect(releaseWorkflow).not.toContain("az keyvault secret");
    expect(releaseWorkflow).not.toContain(
      "postgres flexible-server firewall-rule create",
    );
    expect(releaseWorkflow).not.toContain("npm run db:migrate");
  });

  it("packages Prisma and runs migrations inside App Service", () => {
    expect(packageApp).toContain("--omit=dev");
    expect(packageApp).toContain(
      'test -f "$package_dir/node_modules/prisma/build/index.js"',
    );
    expect(packageApp).toContain("start-production.sh");
    expect(startProduction).toContain(
      "node node_modules/prisma/build/index.js migrate deploy",
    );
    expect(startProduction).toContain("exec node server.js");
  });
});
