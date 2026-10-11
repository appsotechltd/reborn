/** Small "Premium" pill shown on your own profile and account menu. */
export function PremiumBadge({ className = "" }: { className?: string }) {
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full border border-warn-border bg-warn px-2 py-0.5 font-sans text-xs font-semibold tracking-normal text-warn-fg ${className}`}
    >
      <span aria-hidden="true">★</span> Premium
    </span>
  );
}
