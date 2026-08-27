import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Library.js" as Library

Panel {
  id: root
  moduleName: "io.github.daniel-felipe.omashelf"
  ipcTarget: "omashelf"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barLabelMode: setting("barLabel", "percent")
  readonly property int titleLimit: setting("barTitleLimit", 18)
  readonly property int pageStep: Math.max(1, setting("pageStep", 10))

  property string focusSection: "books"
  property int bookIndex: 0
  property bool cursorActive: false
  property bool adding: false
  property bool showFinished: false
  property string pendingDeleteId: ""

  readonly property var current: shelf.current
  readonly property var rows: {
    var list = []
    var sorted = shelf.sorted
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].status === "finished" && !root.showFinished) continue
      list.push(sorted[i])
    }
    return list
  }
  readonly property var selected: rows.length > 0 ? rows[Math.max(0, Math.min(bookIndex, rows.length - 1))] : null

  readonly property var target: (opened && cursorActive && focusSection === "books" && selected) ? selected : current

  readonly property string barLabel: {
    if (!current) return "󰂺"
    var pct = Library.percentText(current)
    var title = current.title.length > titleLimit ? current.title.slice(0, titleLimit - 1) + "…" : current.title
    if (barLabelMode === "icon") return "󰂺"
    if (barLabelMode === "title") return "󰂺 " + title
    if (barLabelMode === "both") return "󰂺 " + title + " " + pct
    return "󰂺 " + pct
  }

  readonly property string barTooltip: {
    if (!current) return "No book in progress"
    var eta = Library.etaText(current)
    return current.title + " — page " + current.currentPage + "/" + current.totalPages
      + " (" + Library.percentText(current) + ")" + (eta !== "" ? " · " + eta : "")
  }

  function ensureCursor() {
    if (adding) { focusSection = "add"; return }
    if (focusSection === "add") focusSection = "books"
    if (rows.length === 0) { bookIndex = 0; return }
    bookIndex = Math.max(0, Math.min(rows.length - 1, bookIndex))
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0 || focusSection !== "books" || rows.length === 0) return
    bookIndex = Math.max(0, Math.min(rows.length - 1, bookIndex + dy))
    pendingDeleteId = ""
    scrollCursorIntoView()
  }

  function setBookCursor(index) {
    cursorActive = true
    focusSection = "books"
    bookIndex = index
  }

  function activateCursor() {
    if (focusSection !== "books" || !selected) return
    shelf.setCurrent(selected.id)
    if (selected.status !== "reading" && selected.status !== "finished") shelf.setStatus(selected.id, "reading")
  }

  function bumpCurrent(pages) {
    if (!target) return
    shelf.advance(target.id, pages)
  }

  function scrollCursorIntoView() {
    if (focusSection !== "books" || !bookColumn) return
    var item = bookColumn.children[bookIndex]
    if (!item || !panelFlick) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(8)
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  // The panel holds the keyboard while open, so a stray `x` must not delete.
  function requestDelete() {
    if (!target) return
    if (pendingDeleteId === target.id) {
      shelf.removeBook(pendingDeleteId)
      pendingDeleteId = ""
      return
    }
    pendingDeleteId = target.id
    deleteArmTimer.restart()
  }

  function startAdding() {
    adding = true
    focusSection = "add"
    cursorActive = true
    Qt.callLater(function() { titleField.forceActiveFocus() })
  }

  function cancelAdding() {
    adding = false
    titleField.text = ""
    authorField.text = ""
    pagesField.text = ""
    focusSection = "books"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function commitAdd() {
    var title = titleField.text.trim()
    var pages = parseInt(pagesField.text, 10)
    if (title === "" || !isFinite(pages) || pages <= 0) return
    shelf.addBook(title, authorField.text.trim(), pages)
    cancelAdding()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    pendingDeleteId = ""
    adding = false
    if (panelFlick) panelFlick.contentY = 0
    ensureCursor()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    id: deleteArmTimer
    interval: 4000
    onTriggered: root.pendingDeleteId = ""
  }

  Service {
    id: shelf
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function status(): string { return root.barTooltip }
    function advance(pages: string): string {
      var n = parseInt(pages, 10)
      if (!root.current || !isFinite(n)) return "no-op"
      var id = root.current.id
      shelf.advance(id, n)
      var updated = shelf.findBook(id)
      return updated ? (updated.currentPage + "/" + updated.totalPages) : "no-op"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    tooltipText: root.barTooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) root.bumpCurrent(1)
      else if (b === Qt.MiddleButton) root.bumpCurrent(-1)
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.bumpCurrent(delta > 0 ? 1 : -1) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.adding ? null : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.adding
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.adding ? root.cancelAdding() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onDeleteRequested: root.requestDelete()
      onTextKey: function(t) {
        if (t === "+" || t === "=") root.bumpCurrent(1)
        else if (t === "-" || t === "_") root.bumpCurrent(-1)
        else if (t === "]") root.bumpCurrent(root.pageStep)
        else if (t === "[") root.bumpCurrent(-root.pageStep)
        else if (t === "a" || t === "A") root.startAdding()
        else if (t === "f" || t === "F") { if (root.target) shelf.finishBook(root.target.id) }
        else if (t === "p" || t === "P") { if (root.target) shelf.toggleStatus(root.target.id) }
        else if (t === "v" || t === "V") root.showFinished = !root.showFinished
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: root.current ? root.current.title : "Nothing on the go"
            meta: root.current
              ? (root.current.author !== "" ? root.current.author : "Unknown author")
              : "Press A to add a book"
            detail: root.current ? Library.percentText(root.current) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰂺"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Column {
            visible: !!root.current
            width: parent.width
            spacing: Style.space(6)

            ProgressTrack {
              width: parent.width
              value: root.current ? Library.percent(root.current) : 0
              foreground: root.foreground
              accent: root.accent
              thickness: Style.space(8)
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              Text {
                textFormat: Text.PlainText
                text: root.current ? ("page " + root.current.currentPage + " / " + root.current.totalPages) : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Item { Layout.fillWidth: true; implicitHeight: 1 }
              Text {
                textFormat: Text.PlainText
                Layout.maximumWidth: parent.width * 0.65
                elide: Text.ElideRight
                text: {
                  if (!root.current) return ""
                  var left = Library.pagesLeft(root.current) + " pages left"
                  var eta = Library.etaText(root.current)
                  return eta !== "" && eta !== "done" ? left + " · " + eta : left
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          RowLayout {
            visible: !!root.target
            width: parent.width
            spacing: Style.spacing.controlGap

            PanelActionButton {
              iconText: "«"
              tooltipText: "Back " + root.pageStep + " pages"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.bumpCurrent(-root.pageStep)
            }
            PanelActionButton {
              iconText: "‹"
              tooltipText: "Back one page"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.bumpCurrent(-1)
            }
            PanelActionButton {
              iconText: "›"
              tooltipText: "Forward one page"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.bumpCurrent(1)
            }
            PanelActionButton {
              iconText: "»"
              tooltipText: "Forward " + root.pageStep + " pages"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.bumpCurrent(root.pageStep)
            }

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              visible: root.target && root.current && root.target.id !== root.current.id
              text: root.target ? root.target.title : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Item {
              Layout.fillWidth: true
              implicitHeight: 1
              visible: !(root.target && root.current && root.target.id !== root.current.id)
            }

            PanelActionButton {
              iconText: "󰄬"
              tooltipText: "Mark finished"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: if (root.target) shelf.finishBook(root.target.id)
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "DASHBOARD"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Grid {
            width: parent.width
            columns: 4
            spacing: Style.space(8)

            StatTile { label: "TODAY"; value: shelf.stats.pagesToday + "p" }
            StatTile { label: "7 DAYS"; value: shelf.stats.pagesThisWeek + "p" }
            StatTile { label: "STREAK"; value: shelf.stats.streak + "d" }
            StatTile { label: "DONE " + Library.todayStamp().slice(2, 4); value: String(shelf.stats.finishedThisYear) }
          }

          Item {
            width: parent.width
            implicitHeight: Style.space(46)

            Row {
              anchors.fill: parent
              spacing: Style.space(6)

              Repeater {
                model: shelf.weekSeries
                Item {
                  required property var modelData
                  required property int index
                  width: (parent.width - parent.spacing * 6) / 7
                  height: parent.height

                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(12)
                    width: parent.width
                    height: Math.max(Style.space(2), (parent.height - Style.space(14)) * modelData.ratio)
                    radius: Style.cornerRadius
                    color: modelData.pages > 0 ? Util.alpha(root.foreground, index === 6 ? 0.9 : 0.45)
                                               : Util.alpha(root.foreground, 0.12)
                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: modelData.pages > 0 ? String(modelData.pages) : "·"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: root.showFinished ? "LIBRARY" : "SHELF"
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.alignment: Qt.AlignVCenter
            }
            Item { Layout.fillWidth: true; implicitHeight: 1 }
            PanelActionButton {
              iconText: root.showFinished ? "󰈈" : "󰈉"
              tooltipText: root.showFinished ? "Hide finished" : "Show finished (" + shelf.finished.length + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.showFinished = !root.showFinished
            }
            PanelActionButton {
              iconText: "󰐕"
              tooltipText: "Add a book"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.adding ? root.cancelAdding() : root.startAdding()
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.rows.length === 0
            width: parent.width
            text: "Shelf is empty. Press A to add a book."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            id: bookColumn
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.rows
              BookRow {
                required property var modelData
                required property int index
                width: bookColumn.width
                book: modelData
                rowIndex: index
              }
            }
          }

          Column {
            visible: root.adding
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              text: "NEW BOOK"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: titleField
              width: parent.width
              placeholderText: "Title"
              foreground: root.foreground
              accent: root.accent
              onAccepted: authorField.forceActiveFocus()
              Keys.onEscapePressed: root.cancelAdding()
            }

            TextField {
              id: authorField
              width: parent.width
              placeholderText: "Author (optional)"
              foreground: root.foreground
              accent: root.accent
              onAccepted: pagesField.forceActiveFocus()
              Keys.onEscapePressed: root.cancelAdding()
            }

            Row {
              width: parent.width
              spacing: Style.spacing.controlGap

              TextField {
                id: pagesField
                width: Style.space(120)
                placeholderText: "Pages"
                foreground: root.foreground
                accent: root.accent
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 100000 }
                onAccepted: root.commitAdd()
                Keys.onEscapePressed: root.cancelAdding()
              }

              Button {
                text: "Add"
                foreground: root.foreground
                accent: root.accent
                enabled: titleField.text.trim() !== "" && pagesField.text !== ""
                onClicked: root.commitAdd()
              }

              Button {
                text: "Cancel"
                foreground: root.foreground
                accent: root.accent
                onClicked: root.cancelAdding()
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: shelf.loadError !== ""
            text: shelf.loadError === "too-large"
              ? "library file is larger than " + Math.round(shelf.maxBytes / 1024) + " KB — not loaded, and nothing will be written to it"
              : shelf.loadError === "not-regular"
                ? "library path is not a regular file — not read, and nothing will be written to it: " + shelf.libraryPath
                : shelf.loadError === "error"
                  ? "library file could not be read — check " + shelf.libraryPath
                  : "library file could not be parsed — fix or remove " + shelf.libraryPath
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.pendingDeleteId !== ""
              ? "press x again to remove " + (root.target ? root.target.title : "")
              : "j/k move · enter set current · +/- page · [ ] " + root.pageStep + " pages · a add · f finish · p pause · v finished · x remove"
            color: root.pendingDeleteId !== "" ? root.foreground : Qt.darker(root.foreground, 2.0)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component StatTile: Rectangle {
    property string label: ""
    property string value: ""

    width: (parent.width - parent.spacing * 3) / 4
    implicitHeight: tileColumn.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: Util.alpha(root.foreground, 0.05)

    Column {
      id: tileColumn
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.0
      }
    }
  }

  component BookRow: CursorSurface {
    id: bookRow
    property var book: null
    property int rowIndex: 0
    readonly property bool isCurrent: root.current && book && root.current.id === book.id

    hasCursor: root.cursorActive && root.focusSection === "books" && root.bookIndex === rowIndex
    current: isCurrent
    foreground: root.foreground
    accent: root.accent
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onEntered: root.setBookCursor(bookRow.rowIndex)
      onClicked: function(mouse) {
        root.setBookCursor(bookRow.rowIndex)
        if (mouse.button === Qt.RightButton) shelf.advance(bookRow.book.id, root.pageStep)
        else if (mouse.button === Qt.MiddleButton) shelf.advance(bookRow.book.id, -root.pageStep)
        else root.activateCursor()
      }
      onWheel: function(wheel) {
        root.setBookCursor(bookRow.rowIndex)
        shelf.advance(bookRow.book.id, wheel.angleDelta.y > 0 ? 1 : -1)
      }
    }

    Column {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(5)

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: bookRow.book && bookRow.book.status === "finished" ? "󰄬"
              : (bookRow.book && bookRow.book.status === "paused" ? "󰏤" : "󰂽")
          color: bookRow.isCurrent ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: bookRow.book ? bookRow.book.title : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: bookRow.isCurrent
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: text !== ""
            text: {
              if (!bookRow.book) return ""
              var parts = []
              if (bookRow.book.author !== "") parts.push(bookRow.book.author)
              if (bookRow.book.status === "finished")
                parts.push(bookRow.book.finished !== "" ? "finished " + bookRow.book.finished : "finished")
              else parts.push(bookRow.book.currentPage + "/" + bookRow.book.totalPages)
              return parts.join(" · ")
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          textFormat: Text.PlainText
          text: bookRow.book ? Library.percentText(bookRow.book) : ""
          color: bookRow.isCurrent ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          Layout.alignment: Qt.AlignVCenter
        }
      }

      ProgressTrack {
        width: parent.width
        value: bookRow.book ? Library.percent(bookRow.book) : 0
        foreground: root.foreground
        accent: root.accent
        muted: !bookRow.isCurrent
        thickness: Style.space(4)
      }
    }
  }
}
