import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { saved: String, saving: String }

  queue() {
    clearTimeout(this.timer)
    clearTimeout(this.clearTimer)
    if (this.hasStatusTarget) this.statusTarget.textContent = this.savingValue
    this.timer = setTimeout(() => this.element.requestSubmit(), 400)
  }

  done(event) {
    if (!this.hasStatusTarget) return
    const ok = event.detail?.success !== false
    this.statusTarget.textContent = ok ? this.savedValue : ""
    clearTimeout(this.clearTimer)
    if (ok) this.clearTimer = setTimeout(() => { this.statusTarget.textContent = "" }, 1600)
  }
}
