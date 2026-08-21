import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.querySelector(".folder-item.is-on")?.scrollIntoView({ inline: "center", block: "nearest", behavior: "auto" })
  }
}
