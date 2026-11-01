// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import monitor

/**
Support for catching operating-system signals.

Not to be confused with $monitor.Signal, a Toit synchronization primitive.

Depending on your use case, choose one of the following approaches:
- $wait: if you need to wait for a signal or signals only once,
- $handle: for a longer-lived handler that owns the current task or a
  dedicated one,
- $Watcher: when something else decides when to stop handling.

Signals are identified by portable constants such as $INT. Each also carries
  the platform's signal number ($Signal.number), and the functions here accept
  either a $Signal or a number, so they interoperate with code that uses raw
  numbers, such as `host.pipe`.

Not supported on embedded platforms. On Windows only $INT, $KILL, $TERM,
  $WINCH and $BREAK are supported. $INFO is only supported on macOS.
*/

/**
A signal.

Signals are compared by identity. The constants in this library are the only
  instances.
*/
class Signal:
  /** The conventional name without the "SIG" prefix, such as "INT". */
  name/string
  /**
  The platform's signal number, or null if this platform doesn't have the
    signal.

  The number differs between platforms: use the constants, not their values.
  Interoperates with `host.pipe`, for example `process.signal signal.TERM`
    and `signal.Signal.from-number (pipe.exit-signal value)`.
  */
  number/int?

  constructor.private_ .name:
    number = signal-number_ name

  /** Returns the signal with the given platform $number, or null. */
  static from-number number/int -> Signal?:
    SIGNALS_.do: | signal/Signal |
      if signal.number == number: return signal
    return null

  /** Whether this platform has the signal. */
  is-supported -> bool:
    return number != null

  hash-code -> int:
    return name.hash-code

  stringify -> string:
    return name

// In Linux numeric order, followed by the signals Linux doesn't have.

/** Hangup: SIGHUP (POSIX). */
HUP ::= Signal.private_ "HUP"
/** Interrupt: SIGINT (POSIX), CTRL_C_EVENT (Windows). */
INT ::= Signal.private_ "INT"
/** Quit: SIGQUIT (POSIX). */
QUIT ::= Signal.private_ "QUIT"
/**
Kill: SIGKILL (POSIX), `TerminateProcess` (Windows).

Can only be sent: $Watcher, $reset and $ignore reject it.
*/
KILL ::= Signal.private_ "KILL"
/** User-defined signal 1: SIGUSR1 (POSIX). */
USR1 ::= Signal.private_ "USR1"
/** User-defined signal 2: SIGUSR2 (POSIX). */
USR2 ::= Signal.private_ "USR2"
/**
Broken pipe: SIGPIPE (POSIX).

The VM ignores it, so writes to a closed pipe or socket throw instead.
  $reset restores the platform default, which terminates the process on such
  writes.
*/
PIPE ::= Signal.private_ "PIPE"
/** Alarm: SIGALRM (POSIX). */
ALRM ::= Signal.private_ "ALRM"
/**
Termination: SIGTERM (POSIX), CTRL_CLOSE_EVENT, CTRL_LOGOFF_EVENT or
  CTRL_SHUTDOWN_EVENT (Windows).

On Windows the system still terminates the process a few seconds later,
  whether or not it is watched.
*/
TERM ::= Signal.private_ "TERM"
/**
Child status change: SIGCHLD (POSIX).

Also sent for subprocesses started with `host.pipe`. $ignore doesn't make the
  kernel reap children automatically, so waiting for subprocesses keeps
  working.
*/
CHLD ::= Signal.private_ "CHLD"
/** Continue: SIGCONT (POSIX). */
CONT ::= Signal.private_ "CONT"
/**
Stop: SIGSTOP (POSIX).

Can only be sent: $Watcher, $reset and $ignore reject it.
*/
STOP ::= Signal.private_ "STOP"
/** Terminal stop: SIGTSTP (POSIX). Not sent in raw mode. */
TSTP ::= Signal.private_ "TSTP"
/** Background terminal read: SIGTTIN (POSIX). */
TTIN ::= Signal.private_ "TTIN"
/** Background terminal write or mode change: SIGTTOU (POSIX). */
TTOU ::= Signal.private_ "TTOU"
/**
Window size change: SIGWINCH (POSIX).

Simulated on Windows by polling the console size.
*/
WINCH ::= Signal.private_ "WINCH"
/** Break: CTRL_BREAK_EVENT (Windows). */
BREAK ::= Signal.private_ "BREAK"
/** Status request: SIGINFO (macOS). */
INFO ::= Signal.private_ "INFO"

SIGNALS_ ::= [
  HUP, INT, QUIT, KILL, USR1, USR2, PIPE, ALRM, TERM, CHLD, CONT, STOP, TSTP,
  TTIN, TTOU, WINCH, BREAK, INFO,
]

group_ ::= signal-init_

/**
Converts a $Signal or a platform signal number to a $Signal.

Throws if a number is not a signal this library knows on this platform.
*/
to-signal_ signal -> Signal:
  if signal is Signal: return signal
  result := Signal.from-number signal
  if not result: throw "UNSUPPORTED"
  return result

/**
Converts a $Signal or a platform signal number to the number the primitives
  take.

Throws if a $Signal is not supported on this platform. A number is passed
  through, so the VM rejects unknown ones.
*/
to-number_ signal -> int:
  if signal is not Signal: return signal
  number := signal.number
  if not number: throw "UNSUPPORTED"
  return number

/**
Receives signals.

While a watcher is open, the signals it watches no longer take their default
  action. Every open watcher for a signal receives it. A signal that arrives
  several times before $wait is called is reported once.

# Example
```
import host.signal

reload-config:
  print "Reloading config"

main:
  watcher := signal.Watcher [signal.HUP]
  try:
    task:: watcher.do: reload-config
    // ...
  finally:
    watcher.close
```
*/
class Watcher:
  resource_ := ?
  state_/ResourceState_? := null
  // State bit `i` reports signals_[i].
  signals_/List ::= []
  mask_/int := 0

  /**
  Constructs a watcher for the given $signals, each a $Signal or a platform
    signal number.

  Throws if a signal is not supported on this platform.
  */
  constructor signals/List:
    signals.do:
      signal := to-signal_ it
      if not signals_.contains signal: signals_.add signal
    mask_ = (1 << signals_.size) - 1
    resource_ = signal-watch_ group_ (Array_.ensure (signals_.map: to-number_ it))
    state_ = ResourceState_ group_ resource_
    add-finalizer this:: close

  /**
  Waits for one of the watched signals and returns it.

  If several are pending, one of them is returned; the others stay pending
    until the next call.

  Throws if the watcher is closed.

  Use $with-timeout to give up after a fixed amount of time.
  */
  wait -> Signal:
    if not state_: throw "CLOSED"
    bits := state_.wait-for-state mask_
    if bits == 0: throw "CLOSED"
    index := bits.count-trailing-zeros
    state_.clear-state (1 << index)
    return signals_[index]

  /**
  Calls $block with each received signal.

  Returns when the watcher is closed. Closing it from another task is the
    intended way to stop the loop.
  */
  do [block] -> none:
    while true:
      sig/Signal? := null
      catch --unwind=(: it != "CLOSED"): sig = wait
      if not sig: return
      block.call sig

  /**
  Stops watching.

  A signal takes its base disposition again once all watchers for it are
    closed.
  */
  close -> none:
    if not state_: return
    critical-do:
      state_.dispose
      signal-unwatch_ resource_ group_
      state_ = null
      remove-finalizer this

/**
Waits for one of the $signals once and returns it.

The signals take their default action again when this function returns.

# Example
```
import host.signal

main:
  sig := signal.wait [signal.INT, signal.TERM]
  print "$sig received, shutting down..."
  // Re-raise the signal. The watcher is closed, so this terminates the
  // process.
  signal.raise sig
```
*/
wait signals/List -> Signal:
  watcher := Watcher signals
  try:
    return watcher.wait
  finally:
    watcher.close

/**
Calls $block with each received signal among $signals.

Loops until the $block leaves it: with a `return` from the enclosing
  function, with `continue.<name>` from an enclosing lambda, or by throwing.
  Either way the watcher is closed and the signals take their default action
  again.

# Example
```
import host.signal

reload-config:
  print "Reloading config"

main:
  task::
    signal.handle [signal.HUP, signal.TERM]: | sig/signal.Signal |
      if sig == signal.HUP:
        reload-config
      else:
        continue.task
```
*/
handle signals/List [block] -> none:
  watcher := Watcher signals
  try:
    watcher.do block
  finally:
    watcher.close

/**
Restores the platform's default action for $signal, a $Signal or a platform
  signal number.

Takes effect while no watcher for $signal is open.
*/
reset signal -> none:
  signal-reset_ (to-number_ signal)

/**
Ignores $signal, a $Signal or a platform signal number.

Takes effect while no watcher for $signal is open.
*/
ignore signal -> none:
  signal-ignore_ (to-number_ signal)

/**
Sends $signal, a $Signal or a platform signal number, to this process.

Typically used to terminate with the right status after cleaning up.

Throws if the signal is not supported on this platform.
*/
raise signal -> none:
  signal-raise_ (to-number_ signal)

signal-init_:
  #primitive.signal.init

signal-watch_ group numbers:
  #primitive.signal.watch

signal-unwatch_ resource group:
  #primitive.signal.unwatch

signal-reset_ number/int:
  #primitive.signal.reset

signal-ignore_ number/int:
  #primitive.signal.ignore

signal-raise_ number/int:
  #primitive.signal.raise

signal-number_ name/string:
  #primitive.signal.number
