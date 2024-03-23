// The sub boxes of a region for each window.
function getSubRegions({ box, num, adj, margin = MARGIN }) {
  const subRegions = [];
  // We want eq margin between any number of children. add offset to entire region
  const OFFSET = margin / 2;
  // Some regions are adjacent to other regions
  const ADJ_OFFSET = offset({ box, num, adj, margin });

  if (box.isVertical) {
    const height = (box.height - margin + ADJ_OFFSET.height) / num;

    for (let i = 0; i < num; i++) {
      subRegions.push({
        width: box.width - margin + ADJ_OFFSET.width,
        height,
        x: box.x + OFFSET + ADJ_OFFSET.x,
        y: box.y + OFFSET + ADJ_OFFSET.y + height * i,
      });
    }
  } else {
    const width = (box.width - MARGIN + ADJ_OFFSET.width) / num;

    for (let i = 0; i < num; i++) {
      subRegions.push({
        width,
        height: box.height - margin + ADJ_OFFSET.height,
        x: box.x + OFFSET + ADJ_OFFSET.x + width * i,
        y: box.y + OFFSET + ADJ_OFFSET.y,
      });
    }
  }

  return subRegions;
}

function offset({ box, num, adj, margin }) {
  const BASE = margin / 2;
  const vert = box.isVertical;
  const offset = {
    x: 0,
    y: 0,
    height: 0,
    width: 0,
  };
  const sizeIncr = BASE / 2;
  const posIncr = BASE / num;

  for (const direction of ["north", "south", "west", "east"]) {
    if (adj[direction] && adj[direction][0] === box.dispId) {
      if (direction === "north") {
        offset.height = offset.height + sizeIncr;
        offset.y = offset.y - posIncr;
      }
      if (direction === "south") {
        offset.height = offset.height + sizeIncr;
      }
      if (direction === "west") {
        offset.width = offset.width + sizeIncr;
        offset.x = offset.x - posIncr;
      }
      if (direction === "east") {
        offset.width = offset.width + sizeIncr;
      }
    }
  }
  return offset;
}

function beforeOrAfter(pt, box, isVertical) {
  const xEnd = box.x + box.width;
  const xMid = box.x + box.width / 2;
  const yEnd = box.y + box.height;
  const yMid = box.x + box.height / 2;
  if (isVertical) {
    return pt.y > yMid ? "After" : "Before";
  } else {
    return pt.x > xMid ? "After" : "Before";
  }
}

function isPtInBox(pt, box) {
  const xEnd = box.x + box.width;
  const yEnd = box.y + box.height;
  return pt.x > box.x && pt.x < xEnd && pt.y > box.y && pt.y < yEnd;
}

function findRegionPosition(pt) {
  const regions = allRegions();
  for (let reg of regions) {
    const subRegions = getSubRegions({
      box: reg.box,
      num: reg.wrappedWindows.length,
      adj: reg.adjacent,
      margin: 0,
    });
    for (let [index, box] of subRegions.entries()) {
      if (isPtInBox(pt, box)) {
        log(reg.name, box);
        return { region: reg, box, index };
      }
    }
  }
}

function allRegions() {
  const screens = Screen.all();
  const allRegions = [];
  for (let screen of screens) {
    const display = STATE[screen.identifier()];
    const regions = Object.values(display.regions);
    for (let region of regions) {
      allRegions.push(region);
    }
  }
  return allRegions;
}

function regionMoveDirection({ curRegion, nextRegion }) {}

// returns wrappedWindow and that window's region
// TODO: windows that are not defined (new)
function findWindow(window) {
  const windowId = window.hash();
  const region = STATE.REGION_MAP[windowId];
  if (region) {
    const windowIndex = region.positionIndex[windowId];
    const wrappedWindow = region.wrappedWindows[windowIndex];
    return { wrappedWindow, region };
  }
  return false;
}

function isBelow(originBox, targetBox) {
  const targetMidpoint = targetBox.y + targetBox.height / 2;
  const originTail = originBox.y + originBox.height - targetMidpoint;
  return (
    originBox.y > targetMidpoint || originTail > targetMidpoint - originBox.y
  );
}

function isAfter(originBox, targetBox) {
  const targetMidpoint = targetBox.x + targetBox.width / 2;
  const originTail = originBox.x + originBox.width - targetMidpoint;
  return (
    originBox.x > targetMidpoint || originTail > targetMidpoint - originBox.x
  );
}

function swapElements({ origin, destination, originIndex, destinationIndex }) {
  [origin[originIndex], destination[destinationIndex]] = [
    destination[destinationIndex],
    origin[originIndex],
  ];
}

function getDistance(origin, target) {
  const { x: x1, y: y1 } = origin;
  const { x: x2, y: y2 } = target;
  return Math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2);
}

// Show connected displays and their ids
function identDisplays() {
  const displays = Screen.all();
  const main = Screen.main();
  const screenFrame = main.flippedVisibleFrame();
  const modal = Modal.build({
    isInput: true,
    hasShadow: true,
    appearance: "dark",
    textDidCommit: () => {
      modal.close();
    },
    origin: (frame) => ({
      x: screenFrame.width / 2 - frame.width / 2,
      y: screenFrame.height / 2 - frame.height / 2,
    }),
  });

  for (const display of displays) {
    modal.text =
      modal.text +
      `${display.identifier()}
       Display Resolution: ${display.frame().width} x ${
         display.frame().height
       }\n\n`;
  }

  modal.text = modal.text + "Press enter to close";
  modal.show();
}

let status;

function indicateMode(mode, state) {
  if (status) {
    status.close();
  }
  status = Modal.build({
    text: state ? `Mode: ${mode}` : `${mode} Mode OFF`,
    duration: STATUS_INFO_DURATION,
    origin: (frame) => ({ x: 0, y: 0 }),
  }).show();
}

function getRegionCount({ screens }) {
  let count = 0;
  for (let screen of screens) {
    log(screen.identifier());
    const regions = REGIONS[screen.identifier()];
    count = count + Object.keys(regions).length;
  }
  return count;
}

// the classic with a twist
function debounce(theFunction, delay, iife) {
  let timer;

  return function (...args) {
    clearTimeout(timer);
    if (iife) {
      iife();
    }

    timer = setTimeout(() => {
      theFunction(...args);
    }, delay);
  };
}
