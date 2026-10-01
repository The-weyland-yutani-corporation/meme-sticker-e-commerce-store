import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const policy = readFileSync(".factory/policy.yml", "utf8");

describe("factory infrastructure authority", () => {
  it("reserves infrastructure changes for the governance lane", () => {
    expect(policy).toMatch(
      /governance:[\s\S]*?controlled_paths:[\s\S]*?-\s+"infra\/\*\*"/,
    );
    expect(policy).toMatch(
      /implementation:[\s\S]*?prohibited_paths:[\s\S]*?-\s+"infra\/\*\*"/,
    );
  });
});
