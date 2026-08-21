import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const current = this.element.querySelector(".folder-item.is-on")
    if (!current) return
    const left = current.offsetLeft - (this.element.clientWidth - current.offsetWidth) / 2
    this.element.scrollLeft = Math.max(0, left)
  }
}
