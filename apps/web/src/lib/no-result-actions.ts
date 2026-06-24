export interface NoResultAction {
  href: string;
  label: string;
}

export function noResultActions(term: string): NoResultAction[] {
  const encodedTerm = encodeURIComponent(term.trim());

  return [
    {
      href: `/suggest?term=${encodedTerm}`,
      label: "Suggest for review"
    },
    {
      href: `/personal?term=${encodedTerm}`,
      label: "Save personal entry"
    }
  ];
}
