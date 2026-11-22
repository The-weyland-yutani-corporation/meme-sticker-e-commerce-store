import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const prismaMocks = vi.hoisted(() => ({
  PrismaClient: vi.fn().mockImplementation(function PrismaClient() {
    return {};
  }),
  PrismaPg: vi.fn().mockImplementation(function PrismaPg() {
    return {};
  }),
}));

vi.mock("@prisma/client", () => ({
  PrismaClient: prismaMocks.PrismaClient,
}));
vi.mock("@prisma/adapter-pg", () => ({
  PrismaPg: prismaMocks.PrismaPg,
}));

describe("getPrisma", () => {
  const globalForPrisma = globalThis as unknown as { prisma?: unknown };

  beforeEach(() => {
    vi.resetModules();
    prismaMocks.PrismaClient.mockClear();
    delete globalForPrisma.prisma;
    vi.stubEnv("DATABASE_URL", "postgresql://localhost:5432/meme_forge_test");
  });

  afterEach(() => {
    delete globalForPrisma.prisma;
    vi.unstubAllEnvs();
  });

  it("reuses a single PrismaClient instance across repeated calls in production", async () => {
    vi.stubEnv("NODE_ENV", "production");
    const { getPrisma } = await import("@/infrastructure/db");

    const first = getPrisma();
    const second = getPrisma();
    const third = getPrisma();

    expect(second).toBe(first);
    expect(third).toBe(first);
    expect(prismaMocks.PrismaClient).toHaveBeenCalledTimes(1);
  });

  it("reuses a single PrismaClient instance outside production", async () => {
    vi.stubEnv("NODE_ENV", "development");
    const { getPrisma } = await import("@/infrastructure/db");

    const first = getPrisma();
    const second = getPrisma();

    expect(second).toBe(first);
    expect(prismaMocks.PrismaClient).toHaveBeenCalledTimes(1);
  });

  it("throws when DATABASE_URL is not configured", async () => {
    vi.stubEnv("DATABASE_URL", "");
    const { getPrisma } = await import("@/infrastructure/db");

    expect(() => getPrisma()).toThrow("DATABASE_URL is not configured");
  });
});
