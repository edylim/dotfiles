/**
 * Actions for keybindings
 */
function doAction(action, direction) {
  const window = Window.focused();
  const windowId = window.hash();
  const region = STATE.REGION_MAP[windowId];
  log(region);
  const index = region.positionIndex[windowId];

  const wrappedWindow = region.wrappedWindows[index];
  // ? region.wrappedWindows[index]
  // : new WrappedWindow({ window, box: region.subRegions[index] });

  region.do({ action, wrappedWindow, direction });
}

function save(slot) {
  log(`SAVING CONFIG "${slot}"`);
  STATE.CURRENT_STORE = slot;
  Storage.set(slot, JSON.stringify(STATE));
}

function load(slot) {
  log(`RESTORING SAVED CONFIG "${slot}"`);
  const data = Storage.get(slot);
  return data ? JSON.parse(data) : null;
}

function del(slot) {
  log(`DELETING SAVED CONFIG "${slot}"`);
  Storage.remove(slot);
}

/**
 * Actions for events
 */
function addNewWinToRegion(window) {
  const newWindow = new WrappedWindow({ window });
  const [displayId, regionName] = DEFAULT_REGION;
  const region = STATE[displayId].regions[regionName];
  STATE.REGION_MAP[newWindow.id] = region;

  region.addWindowStart(newWindow);
  return region;
}
