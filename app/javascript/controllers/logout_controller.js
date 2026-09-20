import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async wipe(event) {
    event.preventDefault()
    try { await caches.delete("kuranotes-v6") } catch {}
    try { await caches.delete("kuranotes-v7") } catch {}
    try {
      // Unsaved offline drafts (prefix must match autosave_controller.js).
      const doomed = []
      for (let i = 0; i < window.localStorage.length; i++) {
        const key = window.localStorage.key(i)
        if (key?.startsWith("kura_draft_")) doomed.push(key)
      }
      doomed.forEach((key) => window.localStorage.removeItem(key))
    } catch {}
    try {
      const reg = await navigator.serviceWorker.getRegistration()
      reg?.active?.postMessage("logout")
    } catch {}
    event.target.submit()
  }
}
