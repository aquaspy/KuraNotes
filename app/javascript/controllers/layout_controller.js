import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "menuButton"]

  connect() {
    this.ui = loadUi()
    this.apply()
    this.onPointer = (event) => {
      if (this.hasMenuTarget && !this.menuTarget.hidden && !event.target.closest(".mobile-menu, [data-layout-target='menuButton']")) {
        this.closeMenu()
      }
    }
    this.onKey = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key === "\\") {
        event.preventDefault()
        this.toggleFocus()
      }
    }
    document.addEventListener("pointerdown", this.onPointer)
    window.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.onPointer)
    window.removeEventListener("keydown", this.onKey)
  }

  toggleFolders() { this.ui.folders = !this.ui.folders; this.persist() }
  toggleList() { this.ui.list = !this.ui.list; this.persist() }

  toggleFocus() {
    const focused = !this.ui.folders && !this.ui.list
    if (focused) {
      this.ui.folders = this.ui.prevFolders ?? true
      this.ui.list = this.ui.prevList ?? true
    } else {
      this.ui.prevFolders = this.ui.folders
      this.ui.prevList = this.ui.list
      this.ui.folders = false
      this.ui.list = false
    }
    this.persist()
  }

  toggleMenu() {
    if (!this.hasMenuTarget) return
    this.menuTarget.hidden = !this.menuTarget.hidden
    if (this.hasMenuButtonTarget) this.menuButtonTarget.setAttribute("aria-expanded", String(!this.menuTarget.hidden))
  }

  closeMenu() {
    if (this.hasMenuTarget) this.menuTarget.hidden = true
    if (this.hasMenuButtonTarget) this.menuButtonTarget.setAttribute("aria-expanded", "false")
  }

  persist() {
    localStorage.setItem("kura.ui", JSON.stringify(this.ui))
    this.apply()
  }

  apply() {
    this.element.classList.toggle("hide-folders", !this.ui.folders)
    this.element.classList.toggle("hide-list", !this.ui.list)
    this.element.classList.toggle("is-focus", !this.ui.folders && !this.ui.list)
  }
}

function loadUi() {
  try {
    const saved = JSON.parse(localStorage.getItem("kura.ui") || "{}")
    return {
      folders: saved.folders !== false,
      list: saved.list !== false,
      prevFolders: saved.prevFolders,
      prevList: saved.prevList
    }
  } catch {
    return { folders: true, list: true }
  }
}
