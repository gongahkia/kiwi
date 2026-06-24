export interface PageInfo {
  cursor: string | null;
  limit: number;
  next_cursor: string | null;
  total: number;
}

export interface PaginatedItems<T> {
  items: T[];
  page: PageInfo;
}

export interface PaginationWindow {
  cursor: string | null;
  limit: number;
  offset: number;
}

const defaultLimit = 50;
const maxLimit = 200;

function numberParam(value: string | null, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

export function paginateItems<T>(
  items: readonly T[],
  searchParams: URLSearchParams,
  options: { defaultLimit?: number; maxLimit?: number } = {}
): PaginatedItems<T> {
  const window = paginationWindow(searchParams, options);
  const pageItems = items.slice(window.offset, window.offset + window.limit);

  return {
    items: [...pageItems],
    page: pageInfo(items.length, window)
  };
}

export function paginationWindow(
  searchParams: URLSearchParams,
  options: { defaultLimit?: number; maxLimit?: number } = {}
): PaginationWindow {
  const configuredDefault = options.defaultLimit ?? defaultLimit;
  const configuredMax = options.maxLimit ?? maxLimit;
  const limit = Math.min(numberParam(searchParams.get("limit"), configuredDefault), configuredMax);
  const cursorOffset = Math.max(0, numberParam(searchParams.get("cursor"), 0));

  return {
    cursor: cursorOffset > 0 ? String(cursorOffset) : null,
    limit,
    offset: cursorOffset
  };
}

export function pageInfo(total: number, window: PaginationWindow): PageInfo {
  const nextOffset = window.offset + window.limit;
  return {
    cursor: window.cursor,
    limit: window.limit,
    next_cursor: nextOffset < total ? String(nextOffset) : null,
    total
  };
}

export function paginationHeaders(page: PageInfo): Headers {
  const headers = new Headers();
  headers.set("x-page-limit", String(page.limit));
  headers.set("x-page-total", String(page.total));
  if (page.next_cursor) headers.set("x-next-cursor", page.next_cursor);
  return headers;
}
