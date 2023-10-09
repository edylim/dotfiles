/**
 * Get the current region defined in REGION_DEFS for given window.
 */
function getCurrentRegionName(window) {
  const screen = window.screen();
  const { x_temp, y } = window.topLeft();
  const regionDefs = REGION_DEFS[screen.identifier()];

  // If top left of window is off screen
  const x = x_temp > 0 ? x_temp : 0;

  // if nothing configured, too bad. That's on you.
  if (!regionDefs) {
    return null;
  }

  return Object.entries(regionDefs)
    .map(([regionName, regionDef]) =>
      y >= regionDef.startPt[1] &&
      y < regionDef.startPt[1] + regionDef.height &&
      x >= regionDef.startPt[0] &&
      x < regionDef.startPt[0] + regionDef.width
        ? regionName
        : "",
    )
    .join("");

  // return Object.entries(regionDefs)
  //   .map(([regionName, regionDef]) => {
  //     log(
  //       `${y} >= ${regionDef.startPt[1]}`,
  //       `${y} < ${regionDef.startPt[1] + regionDef.height}`,
  //       `${x} >= ${regionDef.startPt[0]} || ${x} < 0`,
  //       `${x} < ${regionDef.startPt[0] + regionDef.width}`,
  //       `IS TRUE?: ${x >= regionDef.startPt[0] || x < 0}`,
  //       `IS TRUE2?: ${
  //         y >= regionDef.startPt[1] &&
  //         y < regionDef.startPt[1] + regionDef.height &&
  //         (x >= regionDef.startPt[0] || x < 0) &&
  //         x < regionDef.startPt[0] + regionDef.width
  //       }`,
  //     );
  //     if (
  //       y >= regionDef.startPt[1] &&
  //       y < regionDef.startPt[1] + regionDef.height &&
  //       x >= regionDef.startPt[0] &&
  //       x < regionDef.startPt[0] + regionDef.width
  //     ) {
  //       return regionName;
  //     } else {
  //       return "";
  //     }
  //   })
  //   .join("");
}

function move(direction) {
  const window = Window.focused();
  const screen = window.screen();
  const regionDefs = REGION_DEFS[screen.identifier()];

  const originName = getCurrentRegionName(window);
  const origin = regionDefs[originName];
  const originCrowd = origin.tenants;

  const destinationName = origin.neighbor[direction];
  const destination = destinationName ? regionDefs[destinationName] : origin;
  const destinationCrowd = destination.tenants;
  const destinationCrowdSize = objSize(destinationCrowd);

  const id = window.hash();
  const wrappedWindow = origin.tenants[id] || wrap({ window, destination });
  const destinationCoordinates = getDestinationCoordinates({
    wrappedWindow,
    destination,
  });

  log(objSize(origin.tenants));
  // Destination region already contains windows
  if (destinationCrowdSize) {
    disperseCrowd(origin, destination);
  }
  wrappedWindow.window.setTopLeft({
    x: destinationCoordinates[0],
    y: destinationCoordinates[1],
  });
  sizeForDestination(window, destination);

  destination.tenants[id] = wrappedWindow;
  delete origin.tenants[id];
}

function disperseCrowd(prevRegion, region) {
  const tenants = region.tenants;
  Object.entries(tenants).forEach(([key, tenant]) => {
    log(key);
    sizeForDestination(tenant.window, region);
  });
}

// wrap windows for some awesomesoss
function wrap({ window, destination }) {
  return {
    prevRegionName: null,
    prevRegionPosition: null,
    curRegionName: destination.name,
    curRegionPosition: destination.startPt,
    window,
  };
}

function sizeForDestination(window, region) {
  const tenants = region.tenants;
  const tenantCount = objSize(tenants);
  if (region.splitDim === "width") {
    window.setSize({
      width: region.width / (tenantCount + 1),
      height: region.height,
    });
  }
}

function getDestinationCoordinates({ wrappedWindow, destination }) {
  return wrappedWindow.prevRegionName === destination.name
    ? wrappedWindow.prevRegionPosition
    : destination.startPt;
}

function sizeNeighbors(region) {}

function objSize(obj) {
  return Object.keys(obj).length;
}

function storeConfig(key, config) {
  Storage.set(key, config);
}

function getStoredConfig(key) {
  Storage.get(key);
}

function moveUp() {
  move("up");
}

function moveDown() {
  move("down");
}

function moveLeft() {
  move("left");
}

function moveRight() {
  move("right");
}

function selectUp() {
  const window = Window.focused();
  Window.focused().focusClosestNeighbor("north");
}

function selectDown() {
  const window = Window.focused();
  Window.focused().focusClosestNeighbor("south");
}

function selectLeft() {
  const window = Window.focused();
  Window.focused().focusClosestNeighbor("left");
}

function selectRight() {
  const window = Window.focused();
  Window.focused().focusClosestNeighbor("east");
}
