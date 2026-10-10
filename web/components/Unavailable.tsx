export function Unavailable({ what = "the library" }: { what?: string }) {
  return (
    <div role="status" className="panel mx-auto max-w-read p-6 text-center">
      <h2 className="font-serif text-xl font-semibold">We couldn&apos;t load {what} just now</h2>
      <p className="mt-2 text-muted">The Reborn server isn&apos;t responding. Please try again in a moment.</p>
    </div>
  );
}
