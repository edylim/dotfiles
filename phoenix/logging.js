/**
 * debug logging for debug builds
 *
 * log messages in console using:
 * log stream --process Phoenix --predicate 'composedMessage CONTAINS "<PREFIX>"'
 */

function log(...msg) {
  Phoenix.log(`${DEBUG_PREFIX}: ${msg.join("\n")}`);
}

Event.on("windowDidFocus", (window) => {
  logWindow(window);
});

function logWindow(window) {
  const scr = window.screen();
  const app = window.app();
  const dim = window.size();
  const frame = scr.frame(); // Use 0,0 at top-left
  const vFrame = scr.flippedVisibleFrame(); // visible (minus dock, menu) Use 0,0 at top-left
  log(`App name: ${app.name()} || Title: ${window.title()}`);
  log(`Current screen ID: ${scr.identifier()}`);
  log(` - Num of screens: ${Screen.all().length}`);
  log(` - Num of spaces: ${scr.spaces().length}`);
  log(` - Pixel dimensions:`);
  log(`    - Total: ${frame.width} X ${frame.height}`);
  log(`    - Visible: ${vFrame.width} x ${vFrame.height}`);
  log(` - Num of windows open: ${scr.windows().length}`);
  log(`Window dimensions: ${dim.width}w X ${dim.height}h`);
  log(`\n`);
}
