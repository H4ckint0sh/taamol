import test from "node:test"
import assert from "node:assert/strict"
import {ShareArticle} from "../../assets/js/share_article.js"

async function withHook(navigator, run) {
  const previousNavigator = Object.getOwnPropertyDescriptor(globalThis, "navigator")
  const previousWindow = globalThis.window
  const previousWarn = console.warn
  const prompts = []
  let click
  const label = {textContent: "Share"}
  const el = {
    dataset: {title: "An article", copied: "Link copied", copyPrompt: "Copy this link to share"},
    querySelector: () => label,
    addEventListener: (_event, handler) => { click = handler },
    removeEventListener: (_event, handler) => { assert.equal(handler, click) }
  }
  Object.defineProperty(globalThis, "navigator", {value: navigator, configurable: true})
  globalThis.window = {
    location: {href: "https://example.test/articles/1"},
    prompt: (...args) => prompts.push(args)
  }
  console.warn = () => {}
  const hook = {...ShareArticle, el}
  hook.mounted()

  try {
    await run({click: () => click(), label, prompts})
  } finally {
    hook.destroyed()
    if (previousNavigator) Object.defineProperty(globalThis, "navigator", previousNavigator)
    else delete globalThis.navigator
    globalThis.window = previousWindow
    console.warn = previousWarn
  }
}

test("opens native sharing with the article title and URL", async () => {
  let shared
  await withHook({share: async data => { shared = data }}, async ({click, prompts}) => {
    await click()
    assert.deepEqual(shared, {title: "An article", url: "https://example.test/articles/1"})
    assert.deepEqual(prompts, [])
  })
})

test("canceling native sharing does not copy or prompt", async () => {
  let copied = false
  await withHook({
    share: async () => { throw Object.assign(new Error("Canceled"), {name: "AbortError"}) },
    clipboard: {writeText: async () => { copied = true }}
  }, async ({click, prompts}) => {
    await click()
    assert.equal(copied, false)
    assert.deepEqual(prompts, [])
  })
})

test("copies the link when native sharing is unavailable or fails", async () => {
  for (const share of [undefined, async () => { throw new Error("Unavailable") }]) {
    let copied
    await withHook({share, clipboard: {writeText: async url => { copied = url }}},
      async ({click, label, prompts}) => {
        await click()
        assert.equal(copied, "https://example.test/articles/1")
        assert.equal(label.textContent, "Link copied")
        assert.deepEqual(prompts, [])
      })
  }
})

test("offers the link manually when clipboard access is unavailable or fails", async () => {
  for (const clipboard of [undefined, {writeText: async () => { throw new Error("Denied") }}]) {
    await withHook({clipboard}, async ({click, label, prompts}) => {
      await click()
      assert.equal(label.textContent, "Share")
      assert.deepEqual(prompts, [["Copy this link to share", "https://example.test/articles/1"]])
    })
  }
})
