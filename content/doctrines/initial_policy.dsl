module FieldPolicy
expose act
act view memory =
  (memory, [Wait 500ms])
