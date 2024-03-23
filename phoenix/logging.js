/**
 * debug logging for debug builds
 *
 * log messages in console using:
 * log stream --style compact --process Phoenix --predicate 'NOT composedMessage CONTAINS[c] "Could not"'
 */

const DEBUG_PREFIX = "config_debug";

function log(...msg) {
  for (const m of msg) {
    Phoenix.log(`${DEBUG_PREFIX}: ${JSON.stringify(m, null, 4)}`);
  }
}
