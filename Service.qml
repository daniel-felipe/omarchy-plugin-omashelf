import QtQuick
import Quickshell
import Quickshell.Io
import "Library.js" as Library

// Owns the library file: reads it, writes it, and exposes derived state.
// The file is watched, so edits made by hand (or by the CLI helper) show up
// in the panel without a restart.
QtObject {
  id: root

  property var settings: ({})

  readonly property string libraryPath: {
    var custom = settings && settings.libraryPath ? String(settings.libraryPath).trim() : ""
    if (custom !== "") return custom.replace(/^~/, Quickshell.env("HOME"))
    return Quickshell.env("HOME") + "/.local/state/omarchy/omashelf/library.json"
  }

  property var books: []
  property string currentId: ""
  property bool loaded: false

  readonly property var sorted: Library.sortBooks(books)
  readonly property var stats: Library.stats(books)
  readonly property var weekSeries: Library.weekSeries(books)
  readonly property var reading: books.filter(function(b) { return b.status === "reading" })
  readonly property var finished: books.filter(function(b) { return b.status === "finished" })

  // The book the bar pill talks about: the explicitly selected one when it is
  // still in progress, otherwise the furthest-along active read.
  readonly property var current: {
    var explicit = findBook(currentId)
    if (explicit && explicit.status === "reading") return explicit
    var active = Library.sortBooks(reading)
    return active.length > 0 ? active[0] : null
  }

  function findBook(id) {
    for (var i = 0; i < books.length; i++)
      if (books[i].id === id) return books[i]
    return null
  }

  function indexOf(id) {
    for (var i = 0; i < books.length; i++)
      if (books[i].id === id) return i
    return -1
  }

  function load(raw) {
    var parsed = Library.parseLibrary(raw)
    root.books = parsed.books
    root.currentId = parsed.currentId
    root.loaded = true
  }

  function persist(next) {
    root.books = next
    libraryFile.setText(Library.serialize(next, root.currentId))
  }

  // Pinning a book is state worth keeping, so it goes through the file like
  // every other change instead of living only in this shell session.
  function setCurrent(id) {
    if (root.currentId === id) return
    root.currentId = id
    persist(root.books)
  }

  // ---------------------------------------------------------------- mutation

  function addBook(title, author, totalPages) {
    var book = Library.newBook(title, author, totalPages)
    if (!book) return ""
    var next = books.slice()
    next.push(book)
    root.currentId = book.id
    persist(next)
    return book.id
  }

  // Moves the bookmark and records the delta in today's log so the dashboard
  // (streak, pages today, pace) has something to count.
  function setPage(id, page) {
    var index = indexOf(id)
    if (index < 0) return
    var book = JSON.parse(JSON.stringify(books[index]))
    var target = Math.max(0, Math.min(book.totalPages, Math.round(page)))
    var delta = target - book.currentPage
    if (delta === 0) return

    book.currentPage = target
    if (delta > 0) {
      var stamp = Library.todayStamp()
      var log = book.log.slice()
      var merged = false
      for (var i = log.length - 1; i >= 0; i--) {
        if (log[i].date === stamp) { log[i] = { date: stamp, pages: log[i].pages + delta }; merged = true; break }
      }
      if (!merged) log.push({ date: stamp, pages: delta })
      book.log = log
      if (book.started === "") book.started = stamp
    }
    if (book.currentPage >= book.totalPages) {
      book.status = "finished"
      if (book.finished === "") book.finished = Library.todayStamp()
    } else if (book.status === "finished") {
      book.status = "reading"
      book.finished = ""
    }

    var next = books.slice()
    next[index] = book
    persist(next)
  }

  function advance(id, pages) {
    var book = findBook(id)
    if (!book) return
    setPage(id, book.currentPage + pages)
  }

  function finishBook(id) {
    var book = findBook(id)
    if (!book) return
    setPage(id, book.totalPages)
  }

  function setStatus(id, status) {
    var index = indexOf(id)
    if (index < 0) return
    var book = JSON.parse(JSON.stringify(books[index]))
    book.status = status
    if (status === "finished") {
      book.currentPage = book.totalPages
      if (book.finished === "") book.finished = Library.todayStamp()
    } else {
      book.finished = ""
    }
    var next = books.slice()
    next[index] = book
    persist(next)
  }

  function toggleStatus(id) {
    var book = findBook(id)
    if (!book) return
    if (book.status === "reading") setStatus(id, "paused")
    else if (book.status === "finished") setStatus(id, "reading")
    else setStatus(id, "reading")
  }

  function removeBook(id) {
    var index = indexOf(id)
    if (index < 0) return
    var next = books.slice()
    next.splice(index, 1)
    if (root.currentId === id) root.currentId = ""
    persist(next)
  }

  // FileView won't create the directory for us, and the first write happens
  // whenever the user adds a book — so make the parent up front.
  property Process ensureDir: Process {
    running: true
    command: ["mkdir", "-p", root.libraryPath.replace(/\/[^\/]*$/, "")]
  }

  property FileView libraryFile: FileView {
    path: root.libraryPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: root.load("")
    onFileChanged: reload()
  }
}
