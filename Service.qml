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

  // Refuse to read (or overwrite) a library file that has grown past what the
  // panel is meant to hold. The file is user-writable and the CLI appends to
  // it, so an oversized or runaway file must never be pulled into the shell
  // process.
  //
  // This is fail-closed by construction: `readable` starts false, so the
  // FileView below is built with an empty path and is not attached to the
  // library at all. It is attached only from applyProbe(), i.e. only after a
  // stat has come back under the cap. Nothing — not startup, not a path
  // change — can read the file before that check has run.
  readonly property int maxBytes: Library.MAX_BYTES
  readonly property int maxBooks: Library.MAX_BOOKS
  property int fileBytes: 0
  property bool readable: false
  property string loadError: ""
  // Set while a write we made is expected to come back through the watcher.
  property bool selfWrite: false

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
    root.loadError = parsed.error || ""
    root.loaded = true
  }

  // Detaches FileView from the file, then re-stats it. Detaching first means a
  // file that grew past the cap since the last check cannot be read by anything
  // that happens while the probe is in flight.
  function probe() {
    root.readable = false
    if (sizeProbe.running) sizeProbe.running = false
    sizeProbe.running = true
  }

  // The only place that attaches FileView to the library. Reached only with a
  // size that a stat has already returned.
  function applyProbe(bytes) {
    root.fileBytes = bytes
    if (bytes > root.maxBytes) {
      root.books = []
      root.currentId = ""
      root.loadError = "too-large"
      root.loaded = true
      return
    }
    root.loadError = ""
    // Attaching binds the path, which loads the file; reload() covers the case
    // where it was already attached with the same path.
    if (root.readable) libraryFile.reload()
    else root.readable = true
  }

  // Writes are blocked whenever reads are: a file too big to parse is also a
  // file we must not clobber with the empty list we fell back to.
  function persist(next) {
    if (!root.readable) return
    root.books = next
    // Our own output is bounded by the same caps parseLibrary enforces, so the
    // watcher event it causes needs no re-check — and skipping it keeps the
    // file attached, so rapid edits are never dropped mid-probe.
    root.selfWrite = true
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
    if (books.length >= root.maxBooks) return ""
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

  // Always prints a number: the file's size, or 0 when it does not exist yet.
  // That makes "no output at all" unambiguous — it means the probe did not
  // actually run, which is never treated as a size.
  property Process sizeProbe: Process {
    command: ["sh", "-c", "stat -Lc %s -- \"$1\" 2>/dev/null || echo 0", "sh", root.libraryPath]
    stdout: StdioCollector {
      id: sizeOut
      onStreamFinished: {
        var raw = String(sizeOut.text).trim()
        // An empty or unparseable result leaves the file detached. The recheck
        // timer retries, so a probe that never ran fails closed rather than
        // attaching on a size nobody measured.
        if (raw === "") return
        var n = parseInt(raw, 10)
        if (!isFinite(n) || n < 0) return
        root.applyProbe(n)
      }
    }
  }

  // While detached there is no watcher left to tell us the file shrank back
  // under the cap, so poll slowly instead.
  property Timer recheck: Timer {
    interval: 30000
    repeat: true
    running: !root.readable
    onTriggered: root.probe()
  }

  property FileView libraryFile: FileView {
    path: root.readable ? root.libraryPath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    // Only a real read failure clears the shelf. Detaching sets the path to
    // "" and fails too, and must not be mistaken for an empty library.
    onLoadFailed: { if (root.readable) root.load("") }
    onFileChanged: {
      if (root.selfWrite) { root.selfWrite = false; return }
      root.probe()
    }
    onSaveFailed: root.selfWrite = false
  }

  onLibraryPathChanged: root.probe()
  Component.onCompleted: root.probe()
}
