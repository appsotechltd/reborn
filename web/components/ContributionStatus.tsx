import type { ContributionStatus as Status } from "@/lib/types";

const STYLES: Record<Status, string> = {
  pending: "border-warn-border text-warn-fg bg-warn",
  approved: "border-ok text-ok",
  rejected: "border-bad text-bad",
};

export function ContributionStatus({ status }: { status: Status }) {
  return (
    <span className={`inline-flex rounded-full border px-2.5 py-0.5 text-xs font-semibold capitalize ${STYLES[status] ?? ""}`}>
      {status}
    </span>
  );
}
