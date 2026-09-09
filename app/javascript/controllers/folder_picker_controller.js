import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "list", "option"]

  connect() {
    this.index = -1
    this.onPointerDown = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    this.onViewport = () => {
      if (!this.listTarget.hidden) this.place()
    }
    document.addEventListener("pointerdown", this.onPointerDown)
    window.addEventListener("resize", this.onViewport)
    window.addEventListener("scroll", this.onViewport, true)
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.onPointerDown)
    window.removeEventListener("resize", this.onViewport)
    window.removeEventListener("scroll", this.onViewport, true)
  }

  open() {
    this.applyFilter()
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.place()
  }

  close() {
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.index = -1
    this.optionTargets.forEach((el) => el.classList.remove("is-active"))
  }

  toggle(event) {
    event.preventDefault()
    if (this.listTarget.hidden) {
      this.open()
      this.inputTarget.focus()
    } else {
      this.close()
    }
  }

  filter() {
    if (this.listTarget.hidden) this.open()
    else {
      this.applyFilter()
      this.place()
    }
  }

  pick(event) {
    event.preventDefault()
    this.choose(event.currentTarget.dataset.value ?? "")
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.close()
      return
    }

    const options = this.visibleOptions()
    if (event.key === "ArrowDown") {
      event.preventDefault()
      if (this.listTarget.hidden) this.open()
      this.move(1, this.visibleOptions())
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      if (this.listTarget.hidden) this.open()
      this.move(-1, this.visibleOptions())
    } else if (event.key === "Enter" && !this.listTarget.hidden && this.index >= 0 && options[this.index]) {
      event.preventDefault()
      this.choose(options[this.index].dataset.value ?? "")
    }
  }

  choose(value) {
    this.inputTarget.value = value
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.close()
  }

  applyFilter() {
    const q = this.inputTarget.value.trim().toLowerCase()
    this.optionTargets.forEach((el) => {
      const label = (el.dataset.label || el.textContent).trim().toLowerCase()
      el.hidden = q !== "" && !label.includes(q)
      el.classList.remove("is-active")
    })
    this.index = -1
  }

  move(delta, options) {
    if (!options.length) return
    this.index = (this.index + delta + options.length) % options.length
    options.forEach((el, i) => el.classList.toggle("is-active", i === this.index))
    options[this.index]?.scrollIntoView({ block: "nearest" })
  }

  visibleOptions() {
    return this.optionTargets.filter((el) => !el.hidden)
  }

  place() {
    const rect = this.element.getBoundingClientRect()
    const list = this.listTarget
    const mobile = window.matchMedia("(max-width: 860px)").matches
    const gap = 4
    list.style.position = "fixed"
    if (mobile) {
      list.style.left = "0.5rem"
      list.style.right = "0.5rem"
      list.style.width = "auto"
    } else {
      list.style.left = `${Math.max(8, rect.left)}px`
      list.style.right = "auto"
      list.style.width = `${Math.max(rect.width, 12 * 16)}px`
    }
    const spaceBelow = window.innerHeight - rect.bottom
    if (spaceBelow < 180 && rect.top > spaceBelow) {
      list.style.top = "auto"
      list.style.bottom = `${window.innerHeight - rect.top + gap}px`
    } else {
      list.style.top = `${rect.bottom + gap}px`
      list.style.bottom = "auto"
    }
  }
}
