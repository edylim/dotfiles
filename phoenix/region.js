function Region({ name, config, wrappedWindows, box, subRegions }) {
  this.name = name;

  this.wrappedWindows = wrappedWindows;
  this.subRegions = subRegions;

  this.positionIndex = this.indexWindows();

  this.isVertical = config.vertical_layout;
  this.isDefault = config.is_default;

  this.box = {
    ...box,
    isVertical: this.isVertical,
    name: this.name,
  };

  this.adjacent = config.adjacent;
}

Region.prototype.do = function ({ action, wrappedWindow, direction }) {
  const index = this.positionIndex[wrappedWindow.id];

  const isRegionalVerticalMove =
    this.isVertical && ["north", "south"].includes(direction);
  const isRegionalHorizontalMove =
    !this.isVertical && ["west", "east"].includes(direction);
  const indexDirection = ["east", "south"].includes(direction) ? 1 : -1;

  // if window has region neighbor in direction and is not moving outside region
  if (
    this.wrappedWindows.length > 1 &&
    this.wrappedWindows[index + indexDirection] &&
    (isRegionalVerticalMove || isRegionalHorizontalMove)
  ) {
    this[`${action}Neighbor`]({ currentIndex: index, indexDirection });
  } else {
    this[`${action}Region`]({ wrappedWindow, direction });
  }
};

// Move within same region
Region.prototype.moveNeighbor = function ({ currentIndex, indexDirection }) {
  this.swapNeighbor({ currentIndex, indexDirection });
};

// Move to a new adjacent region
Region.prototype.moveRegion = function ({ wrappedWindow, direction, isSwap }) {
  const adjacent = this.getAdjacent(direction);

  if (adjacent) {
    const [displayId, regionName] = adjacent;
    const display = STATE[displayId];
    const nextRegion = display.regions[regionName];

    this.placeWindows({ wrappedWindow, nextRegion, direction, isSwap });

    STATE.REGION_MAP[wrappedWindow.id] = nextRegion;

    this.reconcileWindows();
    nextRegion.reconcileWindows();
  }
};

Region.prototype.moveRegionName = function ({ wrappedWindow, nextRegion }) {
  //
};

Region.prototype.swapNeighbor = function ({ currentIndex, indexDirection }) {
  const newIndex = currentIndex + indexDirection;
  const windowId = this.wrappedWindows[currentIndex].id;
  const neighborId = this.wrappedWindows[currentIndex + indexDirection].id;

  swapElements({
    origin: this.wrappedWindows,
    destination: this.wrappedWindows,
    originIndex: currentIndex,
    destinationIndex: newIndex,
  });

  this.reindexWindows();
  this.reconcileWindows();
};

Region.prototype.swapRegion = function ({ wrappedWindow, direction }) {
  this.moveRegion({
    wrappedWindow,
    direction,
    isSwap: true,
  });
};

Region.prototype.placeWindows = function ({
  wrappedWindow,
  nextRegion,
  direction,
  isSwap,
}) {
  const closestRegionWindow = nextRegion.findClosestWindow({
    coords: wrappedWindow.topLeft(),
    wrappedWindows: nextRegion.wrappedWindows,
  });

  if (!closestRegionWindow) {
    nextRegion.addWindowStart(wrappedWindow);
    this.removeWindow(wrappedWindow);
  } else {
    const currentIndex = this.positionIndex[wrappedWindow.id];
    const closestIndex = nextRegion.positionIndex[closestRegionWindow.id];
    const currBox = wrappedWindow.frame();
    const nextBox = closestRegionWindow.frame();
    let isNext;

    if (nextRegion.isVertical) {
      isNext = isBelow(currBox, nextBox, direction);
    } else {
      isNext = isAfter(currBox, nextBox, direction);
    }

    if (isSwap) {
      swapElements({
        origin: this.wrappedWindows,
        destination: nextRegion.wrappedWindows,
        originIndex: currentIndex,
        destinationIndex: closestIndex,
      });
    } else {
      isNext
        ? nextRegion.addWindowAfter(wrappedWindow, closestIndex)
        : nextRegion.addWindowBefore(wrappedWindow, closestIndex);
      this.removeWindow(wrappedWindow);
    }
    this.reindexWindows();
    nextRegion.reindexWindows();
  }
};

Region.prototype.findClosestWindow = function ({ coords, wrappedWindows }) {
  let closestDistance, closestWindow;

  // find closest window in new region
  for (const wrappedWindow of wrappedWindows) {
    const distance = getDistance(coords, wrappedWindow.topLeft());

    if (!closestDistance) {
      closestDistance = distance;
      closestWindow = wrappedWindow;
    } else {
      if (closestDistance > distance) {
        closestDistance = distance;
        closestWindow = wrappedWindow;
      }
    }
  }

  return closestWindow;
};

Region.prototype.focusNeighbor = function ({ currentIndex, indexDirection }) {
  const currWindow = this.wrappedWindows[currentIndex];
  const nextWindow = this.wrappedWindows[currentIndex + indexDirection];
  const topLeft = nextWindow.topLeft();

  nextWindow.focus();
  currWindow.unfocus();

  if (MOUSE_FOLLOW) {
    Mouse.move(topLeft);
  }
};

Region.prototype.focusRegion = function ({
  wrappedWindow: currWindow,
  direction,
}) {
  const adjacent = this.getAdjacent(direction);

  // No defined adjacent regions? Just find the closest in aggregate direction
  const adjacentEnough = this.getAlmostAdjacent(direction);

  if (adjacent || adjacentEnough) {
    const [displayId, regionName] = adjacent || adjacentEnough;
    const display = STATE[displayId];
    const nextRegion = display.regions[regionName];
    const wrappedWindows = nextRegion.wrappedWindows;

    if (wrappedWindows.length) {
      const closestRegionWindow = currWindow
        ? nextRegion.findClosestWindow({
            coords: currWindow.topLeft(),
            wrappedWindows: nextRegion.wrappedWindows,
          })
        : wrappedWindows[0];

      if (closestRegionWindow) {
        closestRegionWindow.focus();
        currWindow.unfocus();

        if (MOUSE_FOLLOW) {
          Mouse.move(closestRegionWindow.topLeft());
        }
      }
    } else {
      // Adjacent for direction has no windows, so use next adjacent
      nextRegion.do({
        wrappedWindow: currWindow,
        action: "focus",
        direction,
      });
    }
  }
};

Region.prototype.getAdjacent = function (direction) {
  return this.adjacent[direction];
};

Region.prototype.getAlmostAdjacent = function (direction) {
  return ["east", "south"].includes(direction)
    ? this.adjacent["east"] || this.adjacent["south"]
    : this.adjacent["north"] || this.adjacent["west"];
};

Region.prototype.removeWindow = function (wrappedWindow) {
  const index = this.positionIndex[wrappedWindow.id];
  this.wrappedWindows.splice(index, 1);
  delete STATE.REGION_MAP[wrappedWindow.id];
  this.reindexWindows();
};

Region.prototype.addWindowStart = function (wrappedWindow) {
  this.wrappedWindows.unshift(wrappedWindow);
  this.reindexWindows();
};

Region.prototype.addWindowAfter = function (wrappedWindow, index) {
  this.wrappedWindows.splice(index + 1, 0, wrappedWindow);
  this.reindexWindows();
};

Region.prototype.addWindowBefore = function (wrappedWindow, index) {
  this.wrappedWindows.splice(index, 0, wrappedWindow);
  this.reindexWindows();
};

// sizes and positions all windows in region
Region.prototype.reconcileWindows = function () {
  if (this.wrappedWindows) {
    this.subRegions = getSubRegions({
      box: this.box,
      num: this.wrappedWindows.length,
      adj: this.adjacent,
    });
    for (const [index, window] of this.wrappedWindows.entries()) {
      window.updateBox({ box: this.subRegions[index] });
    }
  }
};

Region.prototype.reindexWindows = function () {
  this.positionIndex = this.indexWindows();
};

Region.prototype.indexWindows = function () {
  const positionIndex = {};
  for (const [index, wrappedWindow] of this.wrappedWindows.entries()) {
    if (wrappedWindow && wrappedWindow.id) {
      positionIndex[wrappedWindow.id] = index;
    }
  }
  return positionIndex;
};
