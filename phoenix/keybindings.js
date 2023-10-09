const moveLeftBinding = Key.on("h", ["command", "control"], moveLeft);
const moveDownBinding = Key.on("j", ["command", "control"], moveDown);
const moveUpBinding = Key.on("k", ["command", "control"], moveUp);
const moveRightBinding = Key.on("l", ["command", "control"], moveRight);

const selectLeftBinding = Key.on("y", ["command", "control"], selectLeft);
const selectDownBinding = Key.on("u", ["command", "control"], selectDown);
const selectUpBinding = Key.on("i", ["command", "control"], selectUp);
const selectRightBinding = Key.on("p", ["command", "control"], selectRight);

// Just a test binding
const testBinding = Key.on("t", ["command", "control"], test);

// Just a test function
function test() {
  const window = Window.focused();
  const screen = window.screen();
  const windows = screen.windows({ visible: false });
  windows.forEach((win) => {
    if (!win.isVisible()) {
      log(win.title());

      // win.raise();
    }
  });
}
