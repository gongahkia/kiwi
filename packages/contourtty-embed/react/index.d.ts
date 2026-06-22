import type { ForwardedRef, ReactElement } from "react";
import type { ContourttyPlayerElement } from "../dist/contourtty-embed.js";

export interface ContourttyPlayerProps {
  src?: string;
  format?: "auto" | "cast" | "ansi";
  cols?: number | string;
  rows?: number | string;
  autoPlay?: boolean;
  autoplay?: boolean;
  loop?: boolean;
  controls?: boolean;
  speed?: number | string;
  className?: string;
  style?: Record<string, unknown>;
  ref?: ForwardedRef<ContourttyPlayerElement>;
}

export function ContourttyPlayer(props: ContourttyPlayerProps): ReactElement;
export default ContourttyPlayer;
