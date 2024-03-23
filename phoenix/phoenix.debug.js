/**
 * Built on Phoenix: https://kasper.github.io/phoenix/
 */

// Configuration file
require("config.js");

// Convenience wrappers
require("display.js");
require("region.js");
require("wrapped-window.js");

// Logging - only for debug builds of Phoenix
// See: https://kasper.github.io/phoenix/getting-started/logging-and-debugging
require("logging.js");

// Some utility functions
require("util.js");

// actions, their keybindings, and events after initialization
require("actions.js");
require("keybindings.js");
require("events.js");

// init stuff
require("init.js");

init();
