import QtQuick
import Quickshell
import Quickshell.Io
import "Library.js" as Library

// Owns the library file: reads it, writes it, and exposes derived state.
// All access goes through the bounded `bin/omashelf-io` helper, which re-checks
// the file about once a second, so edits made by hand (or by the CLI) show up
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

  // The library file is user-writable, its path is user-configurable, and the
  // CLI appends to it, so it is untrusted input: it may be huge, malformed,
  // replaced between two accesses, a symlink, or not a regular file at all.
  //
  // Nothing in QML ever opens it. `bin/omashelf-io` is the only reader and the
  // only writer: it opens the path once with O_NOFOLLOW and O_NONBLOCK, checks
  // on that same descriptor that it is a regular file within the cap, and reads
  // at most that many bytes from it. So the bytes that arrive here are always
  // the bytes that were measured on the descriptor they came from — there is no
  // window between the check and the read for the path to be swapped.
  readonly property int maxBytes: Library.MAX_BYTES
  readonly property int maxBooks: Library.MAX_BOOKS
  property int fileBytes: 0
  // Status reported by the helper: "" until the first check comes back, then
  // "ok", "missing", "too-large", "not-regular" or "error".
  property string status: ""
  // Writable when the file is one we could also read: a file too big (or too
  // strange) to parse is also a file we must not clobber with our fallback.
  readonly property bool readable: status === "ok" || status === "missing"
  property string loadError: ""
  // Set while we are stopping the helper on purpose, so a deliberate restart is
  // not reported as the helper dying.
  property bool restarting: false

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

  // Applies one state event from the helper. Everything that is not a clean
  // read of a bounded regular file leaves the shelf empty and says why.
  function applyState(event) {
    root.status = String(event.status || "error")
    root.fileBytes = parseInt(event.bytes, 10) || 0
    if (root.status === "ok") {
      root.load(String(event.text || ""))
      return
    }
    root.books = []
    root.currentId = ""
    root.loadError = root.status === "missing" ? "" : root.status
    root.loaded = true
  }

  // Writes are blocked whenever reads are, and the helper refuses anything over
  // the cap on its side too.
  function persist(next) {
    if (!root.readable) return
    root.books = next
    ioProc.request({ cmd: "write", text: Library.serialize(next, root.currentId) })
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

  // The helper writes into this directory, and the first write happens whenever
  // the user adds a book — so make the parent up front.
  property Process ensureDir: Process {
    running: true
    command: ["mkdir", "-p", root.libraryPath.replace(/\/[^\/]*$/, "")]
  }

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")

  // Single long-lived helper: it re-checks the file about once a second and
  // emits one JSON line per change, so the widget follows CLI edits without
  // ever opening the file itself.
  property Process io: Process {
    id: ioProc
    running: true
    stdinEnabled: true
    command: ["python3", root.pluginDir + "bin/omashelf-io", root.libraryPath, String(root.maxBytes)]

    function request(command) {
      if (!ioProc.running) return
      ioProc.write(JSON.stringify(command) + "\n")
    }

    // If the helper dies we are blind to the file, so say so rather than
    // showing a stale shelf, and bring it back.
    onExited: {
      if (!root.restarting) {
        root.status = "error"
        root.loadError = "error"
        root.loaded = true
      }
      root.restarting = false
      restartTimer.restart()
    }

    stderr: StdioCollector {
      id: ioErr
      onStreamFinished: { if (String(ioErr.text).trim() !== "") console.warn("omashelf: helper: " + String(ioErr.text).trim()) }
    }

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        var text = String(line).trim()
        if (text === "") return
        var event = null
        try { event = JSON.parse(text) } catch (e) { return }
        if (!event || event.event !== "state") return
        root.applyState(event)
      }
    }
  }

  property Timer restartTimer: Timer {
    id: restartTimer
    interval: 1000
    repeat: false
    onTriggered: ioProc.running = true
  }

  // Objects held in a property are created lazily, so touch the helper here to
  // make sure it is running from the moment the widget exists.
  Component.onCompleted: ioProc.running = true

  // A new path is a different file: drop what the old one gave us and restart
  // the helper against the new one.
  onLibraryPathChanged: {
    root.status = ""
    root.books = []
    root.currentId = ""
    root.loaded = false
    // Stopping is enough: onExited schedules the restart, and by then the
    // command binding has picked up the new path.
    root.restarting = true
    ioProc.running = false
  }
}
