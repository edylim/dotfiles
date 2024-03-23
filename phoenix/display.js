/**
 * Display - A physical display, called a Screen in Phoenix
 */
function Display({ screen }) {
  this.display = screen;

  // frame with box data
  const frame = screen.flippedVisibleFrame();

  // Intrinsic properties of display, don't set these manually
  this.id = screen.identifier();
  this.width = frame.width;
  this.height = frame.height;
  this.x = parseInt(frame.x);
  this.y = parseInt(frame.y);

  // regions defined in config for this display
  this.regions;

  this.box = {
    x: this.x,
    y: this.y,
    width: this.width,
    height: this.height,
    id: this.id,
  };
}

Display.prototype.distribute = function () {
  for (const region of Object.values(this.regions)) {
    region.reconcileWindows();
  }
};
