/** Renders a JSON-LD script, escaping `<` so content can't close the tag. */
export function JsonLd({ data }: { data: unknown }) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(data).replace(/</g, "\\u003c") }}
    />
  );
}

/** schema.org BreadcrumbList for [name, site path] pairs, Home first. */
export function breadcrumbsJsonLd(base: string, items: [string, string][]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [["Home", "/"] as [string, string], ...items].map(([name, path], i) => ({
      "@type": "ListItem",
      position: i + 1,
      name,
      item: `${base}${path === "/" ? "" : path}`,
    })),
  };
}
