import { getPrisma } from "../src/infrastructure/db";

const prisma = getPrisma();

async function main() {
  await prisma.$queryRaw`SELECT 1`;
  console.log("Database connection verified. The catalog is version-controlled.");
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
