import { Controller } from "@hotwired/stimulus"

const DRAFT_PREFIX = "kura_draft_"

export default class extends Controller {
  static targets = ["status"]
  static values = { saved: String, saving: String, offline: String }

  connect() {
    this.dirty = false
    this.restoreDraft()
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
    this.storeDraft()
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
    const ok = event.detail?.success !== false
    if (ok) {
      this.dirty = false
      this.clearDraft()
    }
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = ok ? this.savedValue : ""
    clearTimeout(this.clearTimer)
    if (ok) this.clearTimer = setTimeout(() => { this.statusTarget.textContent = "" }, 1600)
  }

  draftKey() {
    const match = this.element.action.match(/\/notes\/(\d+)/)
    return match ? `${DRAFT_PREFIX}${match[1]}` : null
  }

  storeDraft() {
    const key = this.draftKey()
    if (!key) return
    try {
      window.localStorage.setItem(key, JSON.stringify({
        body: this.bodyField?.value ?? "",
        folder: this.folderField?.value ?? ""
      }))
    } catch {}
  }

  restoreDraft() {
    const key = this.draftKey()
    if (!key) return
    let draft
    try {
      draft = JSON.parse(window.localStorage.getItem(key) || "null")
    } catch {
      return
    }
    if (!draft || typeof draft !== "object") return
    const bodyChanged = typeof draft.body === "string" && this.bodyField && draft.body !== this.bodyField.value
    const folderChanged = typeof draft.folder === "string" && this.folderField && draft.folder !== this.folderField.value
    if (!bodyChanged && !folderChanged) return
    if (bodyChanged) this.bodyField.value = draft.body
    if (folderChanged) this.folderField.value = draft.folder
    this.queue()
  }

  clearDraft() {
    const key = this.draftKey()
    if (!key) return
    try { window.localStorage.removeItem(key) } catch {}
  }

  get bodyField() {
    return this.element.querySelector('[name="note[body]"]')
  }

  get folderField() {
    return this.element.querySelector('[name="note[folder]"]')
  }
}
