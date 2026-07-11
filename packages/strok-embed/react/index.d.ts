import type { ForwardedRef, ReactElement } from "react";
import type { StrokPlayerElement } from "../dist/strok-embed.js";

export interface StrokPlayerProps {
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
  ref?: ForwardedRef<StrokPlayerElement>;
}

export function StrokPlayer(props: StrokPlayerProps): ReactElement;
export default StrokPlayer;
