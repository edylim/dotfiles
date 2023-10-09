// prefix for logs (see logging.js)
const DEBUG_PREFIX = "config_debug";

// MacOs menubar height
const MACOS_MENUBAR_HEIGHT = 25;

// Space btw elements in each defined region
const GUTTER = 50;

// Region padding
const PADDING = 50;

// Define main regions per display
const REGION_DEFS = {
  // Samsung
  "6B4CA138-D495-4204-A447-86033CF7228F": {
    top: {
      name: "top",
      startPt: [0, MACOS_MENUBAR_HEIGHT], // x, y
      width: 4405,
      height: 1440 - MACOS_MENUBAR_HEIGHT / 2,
      neighbor: {
        left: null,
        right: "right",
        up: null,
        down: "bottom",
      },
      splitDim: "width",
      tenants: {},
    },
    bottom: {
      name: "bottom",
      startPt: [0, 1440 + MACOS_MENUBAR_HEIGHT / 2], // x, y
      width: 4405,
      height: 1440 - MACOS_MENUBAR_HEIGHT / 2,
      neighbor: {
        left: null,
        right: "right",
        up: "top",
        down: null,
      },
      splitDim: "width",
      tenants: {},
    },
    right: {
      name: "right",
      startPt: [4405, 0], // x, y
      width: 715,
      height: 2880 - MACOS_MENUBAR_HEIGHT,
      neighbor: {
        left: "top",
        right: null,
        up: null,
        down: null,
      },
      splitDim: "height",
      tenants: {},
    },
  },
  // Dell
  "D3608336-4F1E-4EF2-9F75-DB9316CA3F7D": {},
  // Tablet
  "2A85BD5A-176D-4891-9803-821C1B7DB23D": {},
};
