import Link from "next/link";

export default function NotFound() {
  return (
    <div className="mx-auto max-w-read py-12 text-center">
      <p className="eyebrow">404</p>
      <h1 className="mt-2 font-serif text-3xl font-semibold">We couldn&apos;t find that page</h1>
      <p className="mt-3 text-muted">The idea or source may have moved. Try searching the library instead.</p>
      <div className="mt-6 flex flex-wrap justify-center gap-3">
        <Link href="/" className="btn btn-primary">Today&apos;s idea</Link>
        <Link href="/search" className="btn">Search</Link>
      </div>
    </div>
  );
}

export const metadata = { title: "Not found", robots: { index: false } };
