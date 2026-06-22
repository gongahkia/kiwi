import React, { forwardRef } from "react";
import { defineContourttyPlayer } from "../dist/contourtty-embed.js";

defineContourttyPlayer();

function booleanAttr(value) {
  return value ? "" : undefined;
}

export const ContourttyPlayer = forwardRef(function ContourttyPlayer(props, ref) {
  const {
    autoPlay,
    autoplay,
    loop,
    controls,
    ...rest
  } = props;
  return React.createElement("contourtty-player", {
    ...rest,
    ref,
    autoplay: booleanAttr(autoPlay ?? autoplay),
    loop: booleanAttr(loop),
    controls: booleanAttr(controls),
  });
});

export default ContourttyPlayer;
