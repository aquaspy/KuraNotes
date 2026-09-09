import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["box", "input", "from"]

  open(event) {
    const from = event.currentTarget.dataset.from || ""
    if (this.hasFromTarget) this.fromTarget.value = from
    if (this.hasInputTarget) this.inputTarget.value = from
    this.boxTarget.showModal()
    this.inputTarget?.focus()
    this.inputTarget?.select()
  }

  close() {
    this.boxTarget.close()
  }

  closed() {
    if (this.hasInputTarget) this.inputTarget.value = ""
  }

  backdrop(event) {
    if (event.target === this.boxTarget) this.close()
  }
}
