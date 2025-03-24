// Copyright (C) 2025 Toit contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import io
import reader as old-reader

import .file as file-lib
import .file show RDONLY WRONLY RDWR APPEND CREAT TRUNC
import .pipe show OpenPipe_

interface Stream implements old-reader.Reader:
  in -> io.CloseableReader
  out -> io.CloseableWriter
  close -> none

  /** Deprecated. Use 'read' on $in instead. */
  read -> ByteArray?
  /**
  Deprecated. Use 'write' or 'try-write' on $out instead.
  */
  write x from = 0 to = x.size

  is-a-terminal -> bool

  /** Deprecated. Use the stream as an opaque object directly. */
  fd -> any

  // For internal use.
  fd_ -> any

  /**
  Opens the file at $path for reading.
  */
  constructor.for-read path/string:
    return file-lib.OpenFile_ path RDONLY 0

  /**
  Opens the file at $path for writing.

  If the file does not exist, it is created.  If it exists, it is truncated.
  Uses the given $permissions, modified by the current umask, to set the
    permissions of the file.

  Ignored if the file already exists.
  */
  constructor.for-write path/string --permissions/int=((6 << 6) | (6 << 3) | 6):
    return file-lib.OpenFile_ path (WRONLY | TRUNC | CREAT) permissions

  /**
  Opens the file at $path with the given $flags.

  The $flags parameter is a bitwise-or of the flags defined in this package,
    such as $RDONLY, $WRONLY, $RDWR, $APPEND, $CREAT, and $TRUNC.
  */
  constructor path/string flags/int:
    if (flags & CREAT) != 0:
      // Two argument version with no permissions can't create new files.
      throw "INVALID_ARGUMENT"
    return file-lib.OpenFile_ path flags 0

  /**
  Creates a stream for a file.

  Only works for actual files, not pipes, devices, etc.

  The $flags parameter is a bitwise-or of the flags defined in this package,
    such as $RDONLY, $WRONLY, $RDWR, $APPEND, $CREAT, and $TRUNC.

  The $permissions parameter is the permissions to use when creating the file,
    modified by the current umask. Ignored if the file already exists.
  */
  // Returns an open file.  Only for use on actual files, not pipes, devices, etc.
  constructor path/string flags/int permissions/int:
    return file-lib.OpenFile_ path flags permissions

  /**
  Constructs a pipe to send data to a child process.
  */
  constructor --parent-to-child/True --child-process-name="child process":
    return OpenPipe_ true --child-process-name=child-process-name

  /**
  Constructs a pipe to receive data from a child process.
  */
  constructor --child-to-parent/True --child-process-name="child process":
    return OpenPipe_ false --child-process-name=child-process-name
