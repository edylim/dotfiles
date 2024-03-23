/**
 * Keybindings
 * See: https://kasper.github.io/phoenix/api/keys
 */

// hjkl based bindings
const hjkl = {
  focus: {},
  move: {},
  swap: {},
  sizeUp: {},
  sizeDown: {},
};

// mappings from hjkl to direction
const hjklMap = {
  h: "west",
  j: "south",
  k: "north",
  l: "east",
};

// saved config bindings
const configs = {
  store: {},
  restore: {},
  clear: {},
};

let normalMode;

// Numbers from 1-0. '0' is used as the default register slot for autosave!
const saveSlots = Array.from("1234567890");
const hjklKeys = Array.from("hjkl");

// binds for store, restore and clear

for (const slot of saveSlots) {
  configs["clear"][slot] = Key.on(slot, ["alt", "ctrl", "cmd"], () => {
    del(slot);
  });

  configs["store"][slot] = Key.on(slot, ["alt", "ctrl"], () => {
    save(slot);
  });

  // TODO: support app control
  configs["restore"][slot] = Key.on(slot, ["cmd", "ctrl"], () => {
    init(load(slot));
  });
}

// hjkl binds
for (const key of hjklKeys) {
  // hjkl.swap[key] = new Key(key, ["ctrl", "cmd"], () => {
  //   doAction("sizeUp", hjklMap[key]);
  // });
  //
  // hjkl.swap[key] = new Key(key, ["ctrl", "alt"], () => {
  //   doAction("sizeDown", hjklMap[key]);
  // });

  hjkl.move[key] = new Key(key, ["ctrl", "cmd"], () => {
    doAction("move", hjklMap[key]);
  });

  hjkl.focus[key] = new Key(key, ["ctrl", "alt"], () => {
    doAction("focus", hjklMap[key]);
  });

  hjkl.swap[key] = new Key(key, ["shift", "cmd"], () => {
    doAction("swap", hjklMap[key]);
  });
}

const focusBindings = [...Object.values(hjkl.focus)];
const moveBindings = [...Object.values(hjkl.move)];
const swapBindings = [...Object.values(hjkl.swap)];
const sizeUpBindings = [...Object.values(hjkl.sizeUp)];
const sizeDownBindings = [...Object.values(hjkl.sizeDown)];

const escape = Key.on("escape", ["cmd"], () => {
  enableHjkl();
  disableResize();
  indicateMode("Normal", normalMode);
});

const resizeToggle = Key.on("r", ["cmd", "ctrl"], () => {
  const normalMode = moveBindings[0].isEnabled();
  if (normalMode) {
    disableHjkl();
    enableResize();
    indicateMode("Resize", normalMode);
  } else {
    enableHjkl();
    disableResize();
    indicateMode("Normal", normalMode);
  }
});

function enableResize() {
  for (const binding of sizeUp) {
    binding.enable();
  }
  for (const binding of sizeDown) {
    binding.enable();
  }
}

function disableResize() {
  for (const binding of sizeUp) {
    binding.disable();
  }
  for (const binding of sizeDown) {
    binding.disable();
  }
}

function disableHjkl() {
  for (const binding of focusBindings) {
    binding.disable();
  }
  for (const binding of moveBindings) {
    binding.disable();
  }
  for (const binding of swapBindings) {
    binding.disable();
  }
}

function enableHjkl() {
  for (const binding of focusBindings) {
    binding.enable();
  }
  for (const binding of moveBindings) {
    binding.enable();
  }
  for (const binding of swapBindings) {
    binding.enable();
  }
}

/**
 * Utility functions
 */

// To identify your screens
const identDisp = Key.on(";", ["cmd", "ctrl"], identDisplays);

// Convenience function for testing. No confirmations, no undos!
const deleteAllStores = Key.on("c", ["cmd", "ctrl"], () => {
  log("CLEARING ALL SLOTS!!!");
  for (const slot of saveSlots) {
    Storage.remove(slot);
  }
});
