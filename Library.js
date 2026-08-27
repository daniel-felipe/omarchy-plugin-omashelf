var VERSION = 1

var MAX_BYTES = 1048576
var MAX_BOOKS = 500
var MAX_LOG_ENTRIES = 400
var MAX_TEXT = 300

function todayStamp(date) {
  var d = date || new Date()
  var m = d.getMonth() + 1
  var day = d.getDate()
  return d.getFullYear() + "-" + (m < 10 ? "0" + m : m) + "-" + (day < 10 ? "0" + day : day)
}

function dayOffset(stamp, days) {
  var parts = String(stamp || "").split("-")
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  d.setDate(d.getDate() + days)
  return todayStamp(d)
}

function clampInt(value, min, max) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function makeId() {
  return "bk-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e6).toString(36)
}

function clampText(value, max) {
  var s = String(value === undefined || value === null ? "" : value).trim()
  return s.length > (max || MAX_TEXT) ? s.slice(0, max || MAX_TEXT) : s
}

function normalizeLog(raw) {
  if (!Array.isArray(raw)) return []
  var out = []
  var start = Math.max(0, raw.length - MAX_LOG_ENTRIES)
  for (var i = start; i < raw.length; i++) {
    var entry = raw[i]
    if (!entry || typeof entry !== "object") continue
    var date = String(entry.date || "").trim()
    var pages = Math.round(Number(entry.pages))
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !isFinite(pages) || pages === 0) continue
    out.push({ date: date, pages: pages })
  }
  return out.slice(-MAX_LOG_ENTRIES)
}

function normalizeBook(raw) {
  if (!raw || typeof raw !== "object") return null
  var title = clampText(raw.title)
  if (title === "") return null
  var totalPages = clampInt(raw.totalPages, 1, 100000)
  var currentPage = clampInt(raw.currentPage, 0, totalPages)
  var status = String(raw.status || "").trim().toLowerCase()
  if (status !== "reading" && status !== "finished" && status !== "paused" && status !== "wishlist")
    status = currentPage >= totalPages ? "finished" : "reading"
  return {
    id: clampText(raw.id, 64) || makeId(),
    title: title,
    author: clampText(raw.author),
    totalPages: totalPages,
    currentPage: currentPage,
    status: status,
    started: clampText(raw.started, 10),
    finished: clampText(raw.finished, 10),
    rating: clampInt(raw.rating, 0, 5),
    log: normalizeLog(raw.log)
  }
}

function emptyLibrary(error) {
  return { version: VERSION, books: [], currentId: "", error: error || "" }
}

function parseLibrary(raw) {
  var text = String(raw || "")
  if (text.length > MAX_BYTES) return emptyLibrary("too-large")
  text = text.trim()
  if (text === "") return emptyLibrary()
  var parsed = null
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return emptyLibrary("malformed")
  }
  var list = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.books) ? parsed.books : [])
  if (list.length > MAX_BOOKS) list = list.slice(0, MAX_BOOKS)
  var books = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var book = normalizeBook(list[i])
    if (!book) continue
    if (seen[book.id]) book.id = makeId()
    seen[book.id] = true
    books.push(book)
  }
  var currentId = clampText(parsed && parsed.currentId, 64)
  if (currentId !== "" && !seen[currentId]) currentId = ""

  return { version: VERSION, books: books, currentId: currentId, error: "" }
}

function serialize(books, currentId) {
  return JSON.stringify({ version: VERSION, currentId: currentId || "", books: books }, null, 2) + "\n"
}

function newBook(title, author, totalPages) {
  return normalizeBook({
    id: makeId(),
    title: title,
    author: author,
    totalPages: totalPages,
    currentPage: 0,
    status: "reading",
    started: todayStamp(),
    log: []
  })
}

function percent(book) {
  if (!book || !book.totalPages) return 0
  return Math.max(0, Math.min(1, book.currentPage / book.totalPages))
}

function percentText(book) {
  return Math.round(percent(book) * 100) + "%"
}

function pagesLeft(book) {
  if (!book) return 0
  return Math.max(0, book.totalPages - book.currentPage)
}

function isActive(book) {
  return book && book.status === "reading"
}

function paceForBook(book, days) {
  if (!book || !Array.isArray(book.log) || book.log.length === 0) return 0
  var cutoff = dayOffset(todayStamp(), -(days || 14))
  var pages = 0
  var activeDates = {}
  for (var i = 0; i < book.log.length; i++) {
    var entry = book.log[i]
    if (entry.date < cutoff || entry.pages <= 0) continue
    pages += entry.pages
    activeDates[entry.date] = true
  }
  var activeDays = Object.keys(activeDates).length
  if (activeDays === 0) return 0
  return pages / activeDays
}

function etaText(book) {
  var pace = paceForBook(book, 21)
  var left = pagesLeft(book)
  if (left === 0) return "done"
  if (pace <= 0) return ""
  var days = Math.ceil(left / pace)
  if (days <= 1) return "~1 day left"
  if (days < 14) return "~" + days + " days left"
  if (days < 60) return "~" + Math.round(days / 7) + " weeks left"
  return "~" + Math.round(days / 30) + " months left"
}

function pagesOn(books, stamp) {
  var total = 0
  for (var i = 0; i < books.length; i++) {
    var log = books[i].log || []
    for (var j = 0; j < log.length; j++)
      if (log[j].date === stamp && log[j].pages > 0) total += log[j].pages
  }
  return total
}

function streakDays(books) {
  var stamp = todayStamp()
  if (pagesOn(books, stamp) === 0) {
    stamp = dayOffset(stamp, -1)
    if (pagesOn(books, stamp) === 0) return 0
  }
  var count = 0
  while (pagesOn(books, stamp) > 0 && count < 3650) {
    count += 1
    stamp = dayOffset(stamp, -1)
  }
  return count
}

function stats(books) {
  var list = Array.isArray(books) ? books : []
  var year = todayStamp().slice(0, 4)
  var reading = 0
  var finishedYear = 0
  var pagesYear = 0
  for (var i = 0; i < list.length; i++) {
    var book = list[i]
    if (book.status === "reading") reading += 1
    if (book.status === "finished" && String(book.finished || "").slice(0, 4) === year) finishedYear += 1
    var log = book.log || []
    for (var j = 0; j < log.length; j++)
      if (log[j].date.slice(0, 4) === year && log[j].pages > 0) pagesYear += log[j].pages
  }
  var week = 0
  var stamp = todayStamp()
  for (var d = 0; d < 7; d++) {
    week += pagesOn(list, stamp)
    stamp = dayOffset(stamp, -1)
  }
  return {
    reading: reading,
    finishedThisYear: finishedYear,
    pagesToday: pagesOn(list, todayStamp()),
    pagesThisWeek: week,
    pagesThisYear: pagesYear,
    streak: streakDays(list)
  }
}

function weekSeries(books) {
  var list = Array.isArray(books) ? books : []
  var raw = []
  var stamp = todayStamp()
  for (var d = 6; d >= 0; d--) raw.push(pagesOn(list, dayOffset(stamp, -d)))
  var peak = 0
  for (var i = 0; i < raw.length; i++) peak = Math.max(peak, raw[i])
  var out = []
  for (var k = 0; k < raw.length; k++)
    out.push({ pages: raw[k], ratio: peak > 0 ? raw[k] / peak : 0 })
  return out
}

function sortBooks(books) {
  var list = (books || []).slice()
  var rank = { reading: 0, paused: 1, wishlist: 2, finished: 3 }
  list.sort(function(a, b) {
    var ra = rank[a.status] === undefined ? 4 : rank[a.status]
    var rb = rank[b.status] === undefined ? 4 : rank[b.status]
    if (ra !== rb) return ra - rb
    if (ra === 3) return String(b.finished || "").localeCompare(String(a.finished || ""))
    var pa = percent(a)
    var pb = percent(b)
    if (pa !== pb) return pb - pa
    return a.title.localeCompare(b.title)
  })
  return list
}
