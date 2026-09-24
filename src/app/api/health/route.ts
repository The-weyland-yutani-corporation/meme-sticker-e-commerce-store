import { NextResponse } from "next/server";

export function GET() {
  return NextResponse.json({
    status: "ok",
    service: "meme-sticker-store",
    timestamp: new Date().toISOString(),
  });
}
