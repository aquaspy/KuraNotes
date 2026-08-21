import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { saved: String, saving: String, offline: String }

  connect() {
    this.dirty = false
    this.onOnline = () => {
      if (navigator.onLine && this.dirty) this.element.requestSubmit()
    }
    window.addEventListener("online", this.onOnline)
  }

  disconnect() {
    window.removeEventListener("online", this.onOnline)
    clearTimeout(this.timer)
    clearTimeout(this.clearTimer)
  }

  queue() {
    this.dirty = true
    clearTimeout(this.timer)
    clearTimeout(this.clearTimer)
    if (!navigator.onLine) {
      if (this.hasStatusTarget) this.statusTarget.textContent = this.offlineValue
      return
    }
    if (this.hasStatusTarget) this.statusTarget.textContent = this.savingValue
    this.timer = setTimeout(() => this.element.requestSubmit(), 400)
  }

  done(event) {
    if (!this.hasStatusTarget) return
    const ok = event.detail?.success !== false
    if (ok) this.dirty = false
    this.statusTarget.textContent = ok ? this.savedValue : ""
    clearTimeout(this.clearTimer)
    if (ok) this.clearTimer = setTimeout(() => { this.statusTarget.textContent = "" }, 1600)
  }
}
