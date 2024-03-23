// State of displays and windows. Is the persistence object
// Not intended to be manually edited. Do so at your own risk!
const STATE = {
  // Convenience map of windows to regions
  REGION_MAP: {},
  FOCUSED_WINDOW: null,
  CURRENT_STORE_SLOT: null,
};

// The default storage slot.
const DEFAULT_STORE_SLOT = "0";

// Auto save to default store slot
const DEFAULT_AUTO_SAVE = true;

// Auto save to current store slot
const CURRENT_AUTO_SAVE = false;

// Automatically put windows into defined regions on startup
const AUTO_DISTRIBUTE = true;

// Automatically restore based on saved config, default or last used
const AUTO_RESTORE = true;

// Margin btw windows, regions
const MARGIN = 30;

// How long to display "mode" in seconds. 0 for always visible
const STATUS_INFO_DURATION = 0;

// Reduce margins for the focused window
const GROW_ACTIVE_WINDOW = true;

// Move mouse pointer with window move or selection
const MOUSE_FOLLOW = false;

// TV
const DISP_1 = "6B4CA138-D495-4204-A447-86033CF7228F";
// MONITOR
const DISP_2 = "D3608336-4F1E-4EF2-9F75-DB9316CA3F7D";
// TABLET
const DISP_3 = "2A85BD5A-176D-4891-9803-821C1B7DB23D";

// Default region for window if homeless
const DEFAULT_REGION = [DISP_1, "main_top"];

// TODO: remove adjacent defs
const REGIONS = {
  [DISP_1]: {
    main_top: {
      startPt: [0, 0],
      width: 0.8,
      height: 0.5,
      adjacent: {
        east: [DISP_1, "right_top"],
        south: [DISP_1, "main_bottom"],
        west: [DISP_2, "right"],
      },
      is_default: true,
    },
    right_top: {
      startPt: [0.8, 0],
      width: 0.2,
      height: 0.5,
      adjacent: {
        west: [DISP_1, "main_top"],
        south: [DISP_1, "right_bottom"],
      },
      vertical_layout: true,
    },
    main_bottom: {
      startPt: [0, 0.5],
      width: 0.7,
      height: 0.5,
      adjacent: {
        north: [DISP_1, "main_top"],
        east: [DISP_1, "right_bottom"],
        west: [DISP_3, "right"],
      },
    },
    right_bottom: {
      startPt: [0.7, 0.5],
      width: 0.3,
      height: 0.5,
      adjacent: {
        north: [DISP_1, "right_top"],
        west: [DISP_1, "main_bottom"],
      },
      vertical_layout: true,
    },
  },
  [DISP_2]: {
    left: {
      startPt: [0, 0],
      width: 0.3,
      height: 1,
      adjacent: {
        east: [DISP_2, "right"],
        south: [DISP_3, "left"],
      },
      vertical_layout: true,
    },
    right: {
      startPt: [0.3, 0],
      width: 0.7,
      height: 1,
      adjacent: {
        west: [DISP_2, "left"],
        east: [DISP_1, "main_top"],
        south: [DISP_3, "right"],
      },
    },
  },
  [DISP_3]: {
    right: {
      startPt: [0.5, 0],
      width: 0.5,
      height: 1,
      adjacent: {
        east: [DISP_1, "main_bottom"],
        north: [DISP_2, "right"],
        west: [DISP_3, "left"],
      },
    },
    left: {
      startPt: [0, 0],
      width: 0.5,
      height: 1,
      adjacent: {
        east: [DISP_3, "right"],
        north: [DISP_2, "left"],
      },
      vertical_layout: true,
    },
  },
};
