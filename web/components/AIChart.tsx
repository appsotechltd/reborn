import type { AIChart as Chart } from "@/lib/types";

const COLORS = ["var(--accent)", "var(--apply-border)", "var(--oxblood)", "var(--muted)"];

function fmt(v: number): string {
  return Number.isInteger(v) ? v.toLocaleString("en") : v.toLocaleString("en", { maximumFractionDigits: 2 });
}

/** Draws a Reborn AI chart (bar, line or pie) in plain SVG that follows the theme. */
export function AIChart({ chart }: { chart: Chart }) {
  const summary = `${chart.title}: ${chart.labels
    .map((l, i) => `${l} ${chart.series.map((s) => fmt(s.values[i] ?? 0)).join(" / ")}`)
    .join(", ")}${chart.unit ? ` (${chart.unit})` : ""}`;
  return (
    <figure className="panel p-4" data-testid="ai-chart">
      <figcaption className="font-semibold">{chart.title}</figcaption>
      {chart.kind === "pie" ? <Pie chart={chart} summary={summary} /> : <Axes chart={chart} summary={summary} />}
      {chart.series.length > 1 || chart.kind === "pie" ? (
        <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
          {(chart.kind === "pie" ? chart.labels : chart.series.map((s) => s.name)).map((name, i) => (
            <li key={name + i} className="flex items-center gap-1.5">
              <span aria-hidden className="inline-block size-2.5 rounded-sm" style={{ background: COLORS[i % COLORS.length] }} />
              {name}
            </li>
          ))}
        </ul>
      ) : null}
    </figure>
  );
}

function Axes({ chart, summary }: { chart: Chart; summary: string }) {
  const W = 560;
  const H = 240;
  const pad = { top: 12, right: 8, bottom: 40, left: 44 };
  const all = chart.series.flatMap((s) => s.values);
  const hi = Math.max(0, ...all);
  const lo = Math.min(0, ...all);
  const span = hi - lo || 1;
  const n = chart.labels.length;
  const iw = W - pad.left - pad.right;
  const ih = H - pad.top - pad.bottom;
  const y = (v: number) => pad.top + (1 - (v - lo) / span) * ih;
  const band = iw / n;
  const cx = (i: number) => pad.left + band * (i + 0.5);
  const ticks = [lo, lo + span / 2, hi];
  const labelEvery = Math.max(1, Math.ceil(n / 8));
  const barW = Math.min(36, (band * 0.7) / chart.series.length);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="mt-2 h-auto w-full" role="img" aria-label={summary}>
      {ticks.map((t, i) => (
        <g key={i}>
          <line x1={pad.left} x2={W - pad.right} y1={y(t)} y2={y(t)} stroke="var(--border)" strokeWidth="1" />
          <text x={pad.left - 6} y={y(t) + 4} textAnchor="end" fontSize="11" fill="var(--muted)">
            {fmt(Math.round(t * 100) / 100)}
          </text>
        </g>
      ))}
      {chart.labels.map((l, i) =>
        i % labelEvery === 0 ? (
          <text key={i} x={cx(i)} y={H - pad.bottom + 16} textAnchor="middle" fontSize="11" fill="var(--muted)">
            {l.length > 12 ? `${l.slice(0, 11)}…` : l}
          </text>
        ) : null,
      )}
      {chart.unit ? (
        <text x={pad.left} y={H - 6} fontSize="11" fill="var(--muted)">
          {chart.unit}
        </text>
      ) : null}
      {chart.kind === "bar"
        ? chart.series.map((s, si) =>
            s.values.map((v, i) => {
              const x = cx(i) - (barW * chart.series.length) / 2 + si * barW;
              const top = Math.min(y(v), y(0));
              return (
                <rect key={`${si}-${i}`} x={x} y={top} width={barW - 2} height={Math.max(1, Math.abs(y(v) - y(0)))} rx="3" fill={COLORS[si % COLORS.length]}>
                  <title>{`${s.name}, ${chart.labels[i]}: ${fmt(v)}`}</title>
                </rect>
              );
            }),
          )
        : chart.series.map((s, si) => (
            <g key={si}>
              <path
                d={s.values.map((v, i) => `${i ? "L" : "M"}${cx(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ")}
                fill="none"
                stroke={COLORS[si % COLORS.length]}
                strokeWidth="2.5"
                strokeLinejoin="round"
              />
              {s.values.map((v, i) => (
                <circle key={i} cx={cx(i)} cy={y(v)} r="3.5" fill={COLORS[si % COLORS.length]}>
                  <title>{`${s.name}, ${chart.labels[i]}: ${fmt(v)}`}</title>
                </circle>
              ))}
            </g>
          ))}
    </svg>
  );
}

function Pie({ chart, summary }: { chart: Chart; summary: string }) {
  const values = chart.series[0]?.values ?? [];
  const total = values.reduce((a, v) => a + Math.max(0, v), 0) || 1;
  const R = 90;
  const slices = values.map((v) => (Math.max(0, v) / total) * Math.PI * 2);
  const starts = slices.map((_, i) => -Math.PI / 2 + slices.slice(0, i).reduce((a, b) => a + b, 0));
  return (
    <svg viewBox="0 0 220 220" className="mx-auto mt-2 h-auto w-full max-w-60" role="img" aria-label={summary}>
      {values.map((v, i) => {
        const a = slices[i];
        const start = starts[i];
        const angle = start + a;
        const [x1, y1] = [110 + R * Math.cos(start), 110 + R * Math.sin(start)];
        const [x2, y2] = [110 + R * Math.cos(angle), 110 + R * Math.sin(angle)];
        const d =
          a >= Math.PI * 2 - 1e-6
            ? `M110,${110 - R}A${R},${R} 0 1,1 109.99,${110 - R}Z`
            : `M110,110L${x1.toFixed(2)},${y1.toFixed(2)}A${R},${R} 0 ${a > Math.PI ? 1 : 0},1 ${x2.toFixed(2)},${y2.toFixed(2)}Z`;
        return (
          <path key={i} d={d} fill={COLORS[i % COLORS.length]} stroke="var(--surface)" strokeWidth="2">
            <title>{`${chart.labels[i]}: ${fmt(v)}`}</title>
          </path>
        );
      })}
    </svg>
  );
}
