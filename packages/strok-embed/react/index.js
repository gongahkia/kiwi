import React, { forwardRef } from "react";
import { defineStrokPlayer } from "../dist/strok-embed.js";

defineStrokPlayer();

function booleanAttr(value) {
  return value ? "" : undefined;
}

export const StrokPlayer = forwardRef(function StrokPlayer(props, ref) {
  const {
    autoPlay,
    autoplay,
    loop,
    controls,
    ...rest
  } = props;
  return React.createElement("strok-player", {
    ...rest,
    ref,
    autoplay: booleanAttr(autoPlay ?? autoplay),
    loop: booleanAttr(loop),
    controls: booleanAttr(controls),
  });
});

export default StrokPlayer;
