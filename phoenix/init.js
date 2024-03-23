function init(storedData) {
  let dataToLoad = storedData;
  if (!dataToLoad && AUTO_RESTORE) {
    const defaultData = load(DEFAULT_STORE_SLOT);
    const lastData = load(defaultData?.CURRENT_STORE_SLOT);
    dataToLoad = lastData || defaultData;
  }
  initDisplays(dataToLoad);
}

function initDisplays(storedData) {
  const screens = Screen.all();
  const windows = Window.all({ visible: true });
  const regionCount = getRegionCount({ screens });

  const displayWindows = distributeWindows({
    windows,
    num: regionCount,
  });

  for (const [index, screen] of screens.entries()) {
    const displayData = storedData?.[screen.identifier()];
    const display = new Display({ screen });
    const numRegions = Object.keys(REGIONS[display.id]).length;
    const regionData = displayData?.regions;

    display.regions = initDisplayRegions({
      windows: regionData ? windows : displayWindows,
      regionConfig: REGIONS[display.id],
      regionData: regionData,
      displayBox: display.box,
    });

    STATE[display.id] = display;

    if (AUTO_DISTRIBUTE) {
      display.distribute();
    }
  }
}

function initDisplayRegions({ windows, regionConfig, regionData, displayBox }) {
  const displayRegions = {};
  // const windowsForRegion = [];

  for (const [index, [name, regionCfg]] of Object.entries(
    regionConfig,
  ).entries()) {
    const regionBox = {
      width: parseInt(displayBox.width * regionCfg.width),
      height: parseInt(displayBox.height * regionCfg.height),
      x:
        regionCfg.startPt[0] === 0
          ? displayBox.x
          : parseInt(regionCfg.startPt[0] * displayBox.width + displayBox.x),
      y:
        regionCfg.startPt[1] === 0
          ? displayBox.y
          : parseInt(regionCfg.startPt[1] * displayBox.height + displayBox.y),
      dispId: displayBox.id,
    };

    // Get saved windows for region or set of distributed
    const filteredWindows = regionData
      ? filterWindows({
          windows,
          windowData: regionData[name]?.wrappedWindows,
        }).filter(Boolean)
      : windows.shift(); // TODO: windows can be 2d array of distributed. consider refactor

    // Get nitial "boxes" for windows
    const subRegions = getSubRegions({
      box: regionBox,
      num: filteredWindows.length,
      adj: regionCfg.adjacent,
    });

    // Wrap
    // for (const [index, window] of filteredWindows.entries()) {
    //   log("GHETTO MAP")
    //   log("INDEX" + index);
    //   log(window.title());
    //   windowsForRegion.push(
    //     new WrappedWindow({
    //       window,
    //       box: subRegions[index],
    //     }),
    //   );
    // }
    const windowsForRegion = filteredWindows.map(
      (window, index) =>
        new WrappedWindow({
          window,
          box: subRegions[index],
        }),
    );

    displayRegions[name] = new Region({
      name,
      config: regionCfg,
      wrappedWindows: windowsForRegion,
      box: regionBox,
      subRegions,
    });

    // populate REGION_MAP
    for (const wrappedWindow of windowsForRegion) {
      if (wrappedWindow && wrappedWindow.id) {
        STATE.REGION_MAP[wrappedWindow.id] = displayRegions[name];
        if (Window.focused().hash() === wrappedWindow.id) {
          STATE.FOCUSED_WINDOW = findWindow(Window.focused());
        }
      }
    }
  }

  return displayRegions;
}

function filterWindows({ windows, windowData }) {
  return windowData.map((dataWindow) => {
    return windows.find((window) => window.hash() === dataWindow.id);
  });
}

// Distribute windows into subarrays of roughly same size
function distributeWindows({ windows, num }) {
  const distributed = [];
  const div = Math.floor(windows.length / num);
  let mod = windows.length % num;
  let start = 0;

  for (let i = 0; i < num; i++) {
    if (mod) {
      distributed.push(windows.slice(start, start + div + 1));
      start = start + div + 1;
      mod--;
    } else {
      distributed.push(windows.slice(start, start + div));
      start = start + div;
    }
  }
  return distributed;
}
