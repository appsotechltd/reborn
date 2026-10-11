import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getProfile, loadOr } from "@/lib/server-api";
import { ProfileView } from "./ProfileView";

export const revalidate = 600;

export async function generateMetadata({ params }: { params: Promise<{ handle: string }> }): Promise<Metadata> {
  const { handle } = await params;
  const { data: profile } = await loadOr(() => getProfile(handle), null);
  if (!profile) return { title: "Profile", robots: { index: false } };
  return {
    title: `${profile.display_name} (@${profile.handle})`,
    description: profile.bio || `${profile.display_name}'s favourite ideas on Reborn.`,
    alternates: { canonical: `/u/${profile.handle}` },
    robots: { index: false, follow: true },
  };
}

export default async function Page({ params }: { params: Promise<{ handle: string }> }) {
  const { handle } = await params;
  // A handle no account has is a real 404. When the API is down, the page loads in the browser as before.
  const { data: profile, ok } = await loadOr(() => getProfile(handle), null);
  if (ok && !profile) notFound();
  return <ProfileView handle={handle} />;
}
