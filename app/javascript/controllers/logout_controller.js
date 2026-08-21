import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async wipe(event) {
    event.preventDefault()
    try { await caches.delete("kuranotes-v6") } catch {}
    try { await caches.delete("kuranotes-v7") } catch {}
    try {
      const reg = await navigator.serviceWorker.getRegistration()
      reg?.active?.postMessage("logout")
    } catch {}
    event.target.submit()
  }
}
