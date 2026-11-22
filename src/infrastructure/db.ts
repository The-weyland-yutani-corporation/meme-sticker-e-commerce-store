import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as {
  prisma?: PrismaClient;
};

function createPrismaClient() {
  const connectionString = process.env.DATABASE_URL;

  if (!connectionString) {
    throw new Error("DATABASE_URL is not configured");
  }

  return new PrismaClient({
    adapter: new PrismaPg({ connectionString }),
    log: process.env.NODE_ENV === "development" ? ["warn", "error"] : ["error"],
  });
}

export function getPrisma(): PrismaClient {
  const client = globalForPrisma.prisma ?? createPrismaClient();

  // Always memoize the client (not just outside production). Previously the
  // singleton was only cached in non-production environments, so every
  // production invocation (including the ~15-minute release-health probe)
  // constructed a brand-new PrismaClient with its own connection pool that
  // was never closed. That connection leak exhausted PostgreSQL's
  // max_connections over time, which surfaced as the health endpoint
  // returning HTTP 503 indefinitely.
  globalForPrisma.prisma = client;

  return client;
}
