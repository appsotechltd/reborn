import type { Metadata } from "next";
import { FavoritesView } from "./FavoritesView";

export const metadata: Metadata = { title: "Favourites", robots: { index: false, follow: false } };

export default function Page() {
  return <FavoritesView />;
}
