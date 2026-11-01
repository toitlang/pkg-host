// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import .signal as signal

/**
Support for terminals.

Detects whether a stream is attached to a terminal ($is-terminal), switches the
  terminal to raw mode ($RawMode, $with-raw-mode), and reads the terminal size
  ($size) and watches its changes ($ResizeWatcher, $watch-size).

Not supported on embedded platforms.
*/

group_ ::= terminal-init_

/** Whether the file descriptor $fd is attached to a terminal. */
is-terminal fd/int -> bool:
  return terminal-is-terminal_ fd

/** The size of a terminal. */
class Size:
  columns/int
  rows/int
  /** The width in pixels, if known. */
  pixel-width/int?
  /** The height in pixels, if known. */
  pixel-height/int?

  constructor.private_ values/List:
    columns = values[0]
    rows = values[1]
    pixel-width = (values[2] == 0) ? null : values[2]
    pixel-height = (values[3] == 0) ? null : values[3]

  operator == other -> bool:
    return other is Size
        and columns == other.columns
        and rows == other.rows
        and pixel-width == other.pixel-width
        and pixel-height == other.pixel-height

  hash-code -> int:
    return columns * 31 + rows

  stringify -> string:
    return "$(columns)x$rows"

/**
Returns the size of the terminal attached to $fd.

Throws if $fd is not attached to a terminal.
*/
size --fd/int=1 -> Size:
  return Size.private_ (terminal-size_ fd)

/**
Raw mode of a terminal.

In raw mode input is delivered byte by byte without echo, and the terminal
  does not interpret control characters such as Ctrl-C.

Only one terminal can be in raw mode at a time. The mode is restored on
  $restore and when the process exits.

On POSIX, entering raw mode from a background process stops it
  ($signal.TTOU) unless $signal.TTOU is watched or ignored.

In raw mode Ctrl-C and Ctrl-Z arrive as bytes 3 and 26 instead of
  $signal.INT and $signal.TSTP.
*/
class RawMode:
  resource_ := ?

  /**
  Switches the terminal attached to $fd to raw mode.

  Throws "ALREADY_IN_USE" if a $RawMode is already active.
  */
  constructor --fd/int=0:
    resource_ = terminal-enter-raw_ group_ fd
    add-finalizer this:: restore

  /** Restores the mode the terminal had before. */
  restore -> none:
    if not resource_: return
    critical-do:
      terminal-restore_ resource_ group_
      resource_ = null
      remove-finalizer this

/**
Runs $block with the terminal attached to $fd in raw mode.

The previous mode is restored when the block finishes or throws.
*/
with-raw-mode --fd/int=0 [block]:
  mode := RawMode --fd=fd
  try:
    block.call
  finally:
    mode.restore

/**
Reports size changes of a terminal.

Built on $signal.WINCH, which is only sent for the controlling terminal.
*/
class ResizeWatcher:
  fd_/int
  watcher_/signal.Watcher
  last_/Size := ?

  /** Watches the terminal attached to $fd. */
  constructor --fd/int=1:
    fd_ = fd
    watcher_ = signal.Watcher [signal.WINCH]
    last_ = size --fd=fd

  /** The size returned by the most recent $wait, or the initial size. */
  last -> Size:
    return last_

  /**
  Waits until the terminal size changes and returns the new size.

  Use $with-timeout to give up after a fixed amount of time.
  */
  wait -> Size:
    while true:
      watcher_.wait
      current := size --fd=fd_
      if current == last_: continue
      last_ = current
      return current

  /**
  Calls $block with the new size on each change.

  Only returns when the block returns from the enclosing function or throws.
  */
  do [block] -> none:
    while true:
      block.call wait

  close -> none:
    watcher_.close

/**
Watches terminal size changes, calling given block with the new size on each
  change.
*/
watch-size --fd/int=1 [block]:
  watcher := ResizeWatcher --fd=fd
  try:
    watcher.do block
  finally:
    watcher.close

terminal-init_:
  #primitive.terminal.init

terminal-is-terminal_ fd/int:
  #primitive.terminal.is-terminal

terminal-enter-raw_ group fd/int:
  #primitive.terminal.enter-raw

terminal-restore_ resource group:
  #primitive.terminal.restore

terminal-size_ fd/int:
  #primitive.terminal.size
