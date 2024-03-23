/**
 * Convenience wrapper for PHXWindow
 */
function WrappedWindow({ window, box }) {
  this.window = window;
  this.id = window.hash();

  // Where the window lives
  this.box = box;
  this.float = false;
}

WrappedWindow.prototype.focus = function () {
  log("FOCUS CALLED");
  // Phoenix bug. Sometimes window will lose focus immediately to another
  while (Window.focused().hash() != this.id) {
    this.window.focus();
  }

  if (GROW_ACTIVE_WINDOW) {
    this.grow();
  }

  STATE.FOCUSED_WINDOW = findWindow(Window.focused());
};

WrappedWindow.prototype.unfocus = function () {
  this.shrink();
};

WrappedWindow.prototype.focused = function () {
  return this.id === Window.focused().hash();
};

WrappedWindow.prototype.grow = function () {
  this.update({ modifier: this.withFat.bind(this) });
};

WrappedWindow.prototype.shrink = function () {
  this.update({ modifier: this.withMargin.bind(this) });
};

WrappedWindow.prototype.update = function ({ modifier }) {
  const box = modifier ? modifier(this.box) : this.box;
  this.window.setFrame(box);
};

WrappedWindow.prototype.appName = function () {
  return this.window.app().name();
};

WrappedWindow.prototype.title = function () {
  return this.window.title();
};

WrappedWindow.prototype.topLeft = function () {
  return this.window.topLeft();
};

WrappedWindow.prototype.frame = function () {
  return this.window.frame();
};

WrappedWindow.prototype.updateBox = function ({ box }) {
  const modifier = this.focused()
    ? this.withFat.bind(this)
    : this.withMargin.bind(this);
  this.box = box;
  this.update({ modifier });
};

// Grow beyond region def
WrappedWindow.prototype.withFat = function () {
  const { x, y, width, height } = this.box;
  return {
    x: x - MARGIN / 16,
    y: y - MARGIN / 16,
    width: width + MARGIN / 8,
    height: height + MARGIN / 8,
  };
};

WrappedWindow.prototype.withMargin = function () {
  const { x, y, width, height } = this.box;
  return {
    x: x + MARGIN / 2,
    y: y + MARGIN / 2,
    width: width - MARGIN,
    height: height - MARGIN,
  };
};
