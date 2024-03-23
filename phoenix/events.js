/**
 * Events
 */

let isMouseDragging = false;

const evtStart = Event.on("didLaunch", () => {});
const evtOpen = Event.on("windowDidOpen", (win) => {
  log("WINDOW OPENED");
  log(
    "HASH: " +
      win.hash() +
      " ISNORM: " +
      win.isNormal() +
      " ISVIS: " +
      win.isVisible() +
      " TIT: " +
      win.title(),
  );
  if (win.isNormal()) {
    const region = addNewWinToRegion(win);
    region.reconcileWindows();

    const currentStoreSlot = STATE.CURRENT_STORE_SLOT;

    save(DEFAULT_STORE_SLOT);

    if (
      CURRENT_AUTO_SAVE &&
      currentStoreSlot &&
      currentStoreSlot !== DEFAULT_STORE_SLOT
    ) {
      save(STATE.CURRENT_STORE_SLOT);
    }
  }
});
const evtClose = Event.on("windowDidClose", (win) => {
  log("WINDOW CLOSED");
  log(
    "HASH: " +
      win.hash() +
      " ISNORM: " +
      win.isNormal() +
      " ISVIS: " +
      win.isVisible() +
      " TIT: " +
      win.title(),
  );
  const { wrappedWindow, region } = findWindow(win);
  if (region) {
    region.removeWindow(wrappedWindow);
    region.reconcileWindows();

    const currentStoreSlot = STATE.CURRENT_STORE_SLOT;

    save(DEFAULT_STORE_SLOT);

    if (
      CURRENT_AUTO_SAVE &&
      currentStoreSlot &&
      currentStoreSlot !== DEFAULT_STORE_SLOT
    ) {
      save(STATE.CURRENT_STORE_SLOT);
    }

    region.reconcileWindows();
  }
});

// Fires on MouseUp
const evtMouseLeftClick = Event.on("mouseDidLeftClick", (pt) => {
  log("DID CLICK");
  // windowDidFocus does not fire for some windows, -_-
  const prevFocusedWindow = STATE.FOCUSED_WINDOW?.wrappedWindow;
  const focusedWindow = findWindow(Window.focused()).wrappedWindow;

  if (prevFocusedWindow && prevFocusedWindow.id !== focusedWindow.id) {
    prevFocusedWindow.unfocus();
    focusedWindow.focus();
  }
  isMouseDragging = false;
});

const evtMouseLeftDrag = Event.on(
  "mouseDidLeftDrag",
  debounce(
    (pt) => {
      const { wrappedWindow, region: curRegion } = findWindow(Window.focused());
      log(Window.focused());
      const currentIndex = curRegion.positionIndex[wrappedWindow.id];
      const {
        region: nextRegion,
        index: nextIndex,
        box,
      } = findRegionPosition(pt);
      if (curRegion.name === nextRegion.name) {
        if (currentIndex !== nextIndex) {
          const indexDirection = currentIndex > nextIndex ? -1 : 1;
          curRegion.swapNeighbor({ currentIndex, indexDirection });
        }
      } else {
        // TODO: refactor to region method
        const placement = beforeOrAfter(pt, box, nextRegion.isVertical);
        curRegion.removeWindow(wrappedWindow);
        nextRegion[`addWindow${placement}`](wrappedWindow, nextIndex);
        STATE.REGION_MAP[wrappedWindow.id] = nextRegion;
        curRegion.reconcileWindows();
        nextRegion.reconcileWindows();
      }
    },
    250,
    () => {
      isMouseDragging = true;
    },
  ),
);
const evtMove = Event.on("windowDidMove", (win) => {});
const evtMin = Event.on("windowDidMinimize", (win) => {});
const evtUnmin = Event.on("windowDidUnminimize", (win) => {});
const evtAppLaunch = Event.on("appDidLaunch", (app) => {
  log("APP LAUNCH: " + app.name());
  const app2 = App.get(app.name());
  log(app2.mainWindow().title());
});
// const evtAppTerm = Event.on("appDidTerminate", (app) => {
//   log("APP TERMINATE: " + app.name());
//   const mainWin = app.mainWindow();
//   log(mainWin.title());
// });
