import QtQuick
import Quickshell
import Quickshell.Io
import "Library.js" as Library

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

  readonly property int maxBytes: Library.MAX_BYTES
  readonly property int maxBooks: Library.MAX_BOOKS
  property int fileBytes: 0
  property string status: ""
  // A file too strange to read is also one we must not clobber with our fallback.
  readonly property bool readable: status === "ok" || status === "missing"
  property string loadError: ""
  property string writeError: ""
  property bool restarting: false

  readonly property var sorted: Library.sortBooks(books)
  readonly property var stats: Library.stats(books)
  readonly property var weekSeries: Library.weekSeries(books)
  readonly property var reading: books.filter(function(b) { return b.status === "reading" })
  readonly property var finished: books.filter(function(b) { return b.status === "finished" })

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

  function applyState(event) {
    root.status = String(event.status || "error")
    root.fileBytes = parseInt(event.bytes, 10) || 0
    root.restartDelay = 1000
    if (root.status === "ok") {
      root.load(String(event.text || ""))
      return
    }
    root.books = []
    root.currentId = ""
    root.loadError = root.status === "missing" ? "" : root.status
    root.loaded = true
  }

  function persist(next) {
    if (!root.readable) return
    var text = Library.serialize(next, root.currentId)
    // Re-serializing with indentation can push a file that fits the read cap
    // past it, and the helper would refuse the write.
    if (Library.byteLength(text) > root.maxBytes) {
      root.writeError = "too-large"
      ioProc.request({ cmd: "poll" })
      return
    }
    root.books = next
    ioProc.request({ cmd: "write", text: text })
  }

  function setCurrent(id) {
    if (root.currentId === id) return
    root.currentId = id
    persist(root.books)
  }

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

  property Process ensureDir: Process {
    running: true
    command: ["mkdir", "-p", root.libraryPath.replace(/\/[^\/]*$/, "")]
  }

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")

  property Process io: Process {
    id: ioProc
    running: true
    stdinEnabled: true
    command: ["python3", root.pluginDir + "bin/omashelf-io", root.libraryPath, String(root.maxBytes)]

    function request(command) {
      if (!ioProc.running) return
      ioProc.write(JSON.stringify(command) + "\n")
    }

    onExited: {
      if (!root.restarting) {
        root.status = "error"
        root.loadError = "error"
        root.loaded = true
        root.restartDelay = Math.min(root.restartDelay * 2, 60000)
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
        if (!event) return
        if (event.event === "write") {
          root.writeError = event.ok ? "" : "refused"
          if (!event.ok) console.warn("omashelf: write refused: " + String(event.message || ""))
          return
        }
        if (event.event !== "state") return
        root.applyState(event)
      }
    }
  }

  property int restartDelay: 1000

  property Timer restartTimer: Timer {
    id: restartTimer
    interval: root.restartDelay
    repeat: false
    onTriggered: ioProc.running = true
  }

  // Properties hold their objects lazily, so touch the helper to start it.
  Component.onCompleted: ioProc.running = true

  onLibraryPathChanged: {
    root.status = ""
    root.books = []
    root.currentId = ""
    root.loadError = ""
    root.writeError = ""
    root.loaded = false
    root.restartDelay = 1000
    // onExited schedules the restart, by which time command has the new path.
    root.restarting = true
    ioProc.running = false
  }
}
