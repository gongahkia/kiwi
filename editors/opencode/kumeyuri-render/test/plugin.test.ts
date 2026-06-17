import { describe, expect, test } from "bun:test"
import plugin from "../plugins/kumeyuri-render"

describe("kumeyuri opencode plugin", () => {
  test("registers render tool", async () => {
    const hooks = await plugin({} as never)
    expect(hooks.tool?.kumeyuri_render).toBeDefined()
  })
})
