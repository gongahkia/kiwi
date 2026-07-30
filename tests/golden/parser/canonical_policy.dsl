module FieldPolicy
expose act
act view memory =
  let danger = dangerScore view
  in
  case nearestCasualty view of
    Some ally ->
      if danger < 0.60
      then (memory, moveAndStabilise view ally)
      else (memory, requestCover ally.position)
    None ->
      engageOrAdvance view memory
