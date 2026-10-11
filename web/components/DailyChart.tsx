import { weekday } from "@/lib/engage";

/** Two-series line chart (signups, active readers) for the last 30 days, in plain SVG. */
export function DailyChart({ days }: { days: { day: string; signups: number; active: number }[] }) {
  const W = 640;
  const H = 220;
  const pad = { top: 16, right: 12, bottom: 28, left: 36 };
  const max = Math.max(1, ...days.map((d) => Math.max(d.signups, d.active)));
  const n = Math.max(1, days.length - 1);
  const x = (i: number) => pad.left + (i / n) * (W - pad.left - pad.right);
  const y = (v: number) => pad.top + (1 - v / max) * (H - pad.top - pad.bottom);
  const line = (key: "signups" | "active") => days.map((d, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(d[key]).toFixed(1)}`).join(" ");
  const ticks = [0, Math.round(max / 2), max];
  const labelEvery = Math.max(1, Math.ceil(days.length / 6));
  const total = (k: "signups" | "active") => days.reduce((a, d) => a + d[k], 0);

  return (
    <figure>
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-labelledby="daily-chart-title">
        <title id="daily-chart-title">
          {`Signups and active readers per day over the last ${days.length} days: ${total("signups")} signups in total, up to ${Math.max(0, ...days.map((d) => d.active))} active readers a day.`}
        </title>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={pad.left} x2={W - pad.right} y1={y(t)} y2={y(t)} stroke="var(--border)" strokeWidth="1" />
            <text x={pad.left - 6} y={y(t) + 4} textAnchor="end" fontSize="11" fill="var(--muted)">
              {t}
            </text>
          </g>
        ))}
        {days.map((d, i) =>
          i % labelEvery === 0 || i === days.length - 1 ? (
            <text key={d.day} x={x(i)} y={H - 8} textAnchor="middle" fontSize="11" fill="var(--muted)">
              {`${weekday(d.day).slice(0, 2)} ${d.day.slice(8)}`}
            </text>
          ) : null,
        )}
        <path d={line("active")} fill="none" stroke="var(--apply-border)" strokeWidth="2.5" strokeLinejoin="round" />
        <path d={line("signups")} fill="none" stroke="var(--accent)" strokeWidth="2.5" strokeLinejoin="round" />
        {days.map((d, i) => (
          <circle key={d.day} cx={x(i)} cy={y(d.signups)} r="2.5" fill="var(--accent)">
            <title>{`${d.day}: ${d.signups} signups, ${d.active} active`}</title>
          </circle>
        ))}
      </svg>
      <figcaption className="mt-2 flex gap-4 text-sm text-muted">
        <span className="flex items-center gap-1.5">
          <span aria-hidden="true" className="inline-block h-0.5 w-4 bg-accent" /> Signups
        </span>
        <span className="flex items-center gap-1.5">
          <span aria-hidden="true" className="inline-block h-0.5 w-4 bg-apply-border" /> Active readers
        </span>
      </figcaption>
    </figure>
  );
}
