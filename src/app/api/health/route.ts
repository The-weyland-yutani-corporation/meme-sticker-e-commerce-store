import { NextResponse } from "next/server";
import { getPrisma } from "@/infrastructure/db";

export async function GET() {
  try {
    await getPrisma().$queryRaw`SELECT 1`;
    return NextResponse.json({
      status: "ok",
      service: "meme-sticker-store",
      version: process.env.RELEASE_SHA ?? "development",
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error("health.database_unavailable", error);
    return NextResponse.json(
      {
        status: "unhealthy",
        service: "meme-sticker-store",
        version: process.env.RELEASE_SHA ?? "development",
        timestamp: new Date().toISOString(),
      },
      { status: 503 },
    );
  }
}
