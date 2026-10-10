// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import io
import monitor show ResourceState_

import .directory as directory

/**
Unix domain stream sockets for local interprocess communication.

Supports filesystem paths on Linux and macOS/BSD. Requires a runtime with the
  `unix_socket` primitives. Other platforms are not supported.
Paths must be nonempty, contain no NUL bytes, and fit the operating system's
  socket address limit, measured in encoded bytes. Relative paths are resolved
  against the Toit process current directory; path queries return the resolved
  pathname. Queries throw `ILLEGAL_UTF_8` if a pathname supplied by an external
  peer is not valid UTF-8.

Listening never removes an existing file. Closing a socket never removes its
  pathname; the application must delete it when appropriate. Prefer a private
  directory for socket files. Permissions follow the operating system's rules
  and the process umask.
*/

/**
Connects to the socket at $path.

Waits for a pending connection to complete. Throws an operating system error
  if the connection fails, including when the listener's queue is full.
*/
connect path/string -> Socket:
  socket := Socket.create_ (connect_ resource-group_ (absolute-path_ path))
  succeeded := false
  try:
    socket.wait_ WRITE_
    state := socket.ensure-state_
    error := error-number_ state.resource
    if error != 0: throw (error_ error)
    succeeded = true
    return socket
  finally:
    if not succeeded: socket.close

/**
Listens for connections at $path with the given $backlog.

The path must not already exist. The application owns the pathname and must
  remove it after closing the listener. If binding succeeds but a subsequent
  operation fails, the pathname may still have been created.
It is an error if $backlog is negative.
*/
listen path/string --backlog/int=10 -> ServerSocket:
  return ServerSocket.create_ (listen_ resource-group_ (absolute-path_ path) backlog)

READ_  ::= 1 << 0
WRITE_ ::= 1 << 1
CLOSE_ ::= 1 << 2
ERROR_ ::= 1 << 3

resource-group_ ::= init_

absolute-path_ path/string -> string:
  if path == "": throw "INVALID_ARGUMENT"
  if path.starts-with "/": return path
  // The OS working directory is shared by all Toit processes. Use the
  // per-process directory, just as host.file and host.directory do.
  return "$(directory.cwd)/$path"

abstract class SocketResource_:
  state_/ResourceState_? := null

  constructor resource:
    succeeded := false
    try:
      state_ = ResourceState_ resource-group_ resource
      add-finalizer this:: close
      succeeded = true
    finally:
      if not succeeded:
        if state_: state_.dispose
        close_ resource-group_ resource

  /**
  Returns the bound local pathname, or null for an unnamed endpoint.

  Throws `ILLEGAL_UTF_8` if the pathname is not valid UTF-8.
  */
  local-path -> string?:
    return path_ ensure-state_.resource false

  /**
  Closes the socket and wakes tasks waiting for it.

  Pending operations throw `ALREADY_CLOSED`. Repeated calls have no effect.
  Does not remove the socket pathname.
  */
  close -> none:
    critical-do:
      state := state_
      if not state: return
      state_ = null
      group := state.group
      resource := state.resource
      state.dispose
      close_ group resource
      remove-finalizer this

  ensure-state_ -> ResourceState_:
    state := state_
    if not state: throw "ALREADY_CLOSED"
    return state

  wait_ bits/int -> none:
    state := ensure-state_
    events := state.wait-for-state (bits | CLOSE_ | ERROR_)
    if not state_ or events == 0: throw "ALREADY_CLOSED"
    if events & ERROR_ != 0:
      error := error-number_ state.resource
      if error != 0:
        close
        throw (error_ error)

/**
A connected Unix domain stream socket.

Provides $in and $out streams. Closing $out sends EOF to the peer while
  leaving $in usable. Closing $in only closes the reader; use $close to
  release the socket itself.
*/
class Socket extends SocketResource_ with io.CloseableInMixin io.CloseableOutMixin:
  constructor.create_ resource:
    super resource

  /**
  Returns the peer pathname, or null for an unnamed endpoint.

  Throws `ILLEGAL_UTF_8` if the peer supplied a pathname that is not valid UTF-8.
  */
  peer-path -> string?:
    return path_ ensure-state_.resource true

  read_ -> ByteArray?:
    while true:
      state := ensure-state_
      result := read-socket_ state.group state.resource
      if result != -1: return result
      state.clear-state READ_
      wait_ READ_

  try-write_ data/io.Data from/int to/int -> int:
    while true:
      state := ensure-state_
      result := write_ state.group state.resource data from to
      if result != -1: return result
      state.clear-state WRITE_
      wait_ WRITE_

  close-reader_ -> none:
    // Closing the reader leaves the socket open, as with TCP sockets.

  close-writer_ -> none:
    state := state_
    if state: close-write_ state.group state.resource

/** A listener for Unix domain stream connections. */
class ServerSocket extends SocketResource_:
  constructor.create_ resource:
    super resource

  /**
  Accepts the next connection, waiting if necessary.

  Throws `ALREADY_CLOSED` if the listener is closed while waiting.
  */
  accept -> Socket:
    while true:
      state := ensure-state_
      resource := accept_ state.group state.resource
      if resource: return Socket.create_ resource
      state.clear-state READ_
      wait_ READ_

init_:
  #primitive.unix-socket.init

connect_ group path:
  #primitive.unix-socket.connect

listen_ group path backlog:
  #primitive.unix-socket.listen

accept_ group resource:
  #primitive.unix-socket.accept

read-socket_ group resource:
  #primitive.unix-socket.read

write_ group resource data/io.Data from/int to/int -> int:
  #primitive.unix-socket.write: | error |
    if error != "WRONG_BYTES_TYPE": throw error
    if from < 0 or from > to or to > data.byte-size: throw "OUT_OF_BOUNDS"
    // Return after a partial write so the stream can wait for readiness.
    List.chunk-up from to 4096: | chunk-from chunk-to chunk-size |
      chunk := ByteArray.from data chunk-from chunk-to
      written := write_ group resource chunk 0 chunk-size
      if written != chunk-size:
        if written == -1:
          if chunk-from == from: return -1
          return chunk-from - from
        return chunk-from - from + written
    return to - from

close-write_ group resource:
  #primitive.unix-socket.close-write

close_ group resource:
  #primitive.unix-socket.close

error-number_ resource -> int:
  #primitive.unix-socket.error-number

error_ number/int -> string:
  #primitive.unix-socket.error

path_ resource peer/bool -> string?:
  bytes := path-bytes_ resource peer
  return bytes ? bytes.to-string : null

path-bytes_ resource peer/bool -> ByteArray?:
  #primitive.unix-socket.path
