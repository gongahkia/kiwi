export function formatOpenGraphAlternatives(contemporaries: string[], limit = 3): string | null {
  if (contemporaries.length === 0) return null;

  const visible = contemporaries.slice(0, limit);
  const hiddenCount = contemporaries.length - visible.length;
  const suffix = hiddenCount > 0 ? ` · +${hiddenCount} more` : "";

  return `Alternatives: ${visible.join(" · ")}${suffix}`;
}
