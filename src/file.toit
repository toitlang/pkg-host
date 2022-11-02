// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import reader show Reader
import writer show Writer

// Manipulation of files on a filesystem.  Currently not available on embedded
// targets.  Names work best when imported without "show *".

// Flags for file.Stream second constructor argument.  Analogous to the
// second argument to the open() system call.
RDONLY ::= 1
WRONLY ::= 2
RDWR ::= 3
APPEND ::= 4
CREAT ::= 8
TRUNC ::= 0x10

// Indices for the array returned by file.stat.
ST_DEV ::= 0
ST_INO ::= 1
ST_MODE ::= 2
ST_TYPE ::= 3
ST_NLINK ::= 4
ST_UID ::= 5
ST_GID ::= 6
ST_SIZE ::= 7
ST_ATIME ::= 8
ST_MTIME ::= 9
ST_CTIME ::= 10

// Filesystem entry types for the ST_TYPE field of file.stat.
FIFO ::= 0
CHARACTER_DEVICE ::= 1
DIRECTORY ::= 2
BLOCK_DEVICE ::= 3
REGULAR_FILE ::= 4
SYMBOLIC_LINK ::= 5
SOCKET ::= 6

// An open file with a current position.  Corresponds in many ways to a file
// descriptor in Posix.
class Stream implements Reader:
  fd_ := ?

  constructor.internal_ .fd_:

  /**
  Opens the file at $path for reading.
  */
  constructor.for_read path/string:
    return Stream path RDONLY 0

  /**
  Opens the file at $path for writing.

  If the file does not exist, it is created.  If it exists, it is truncated.
  Uses the given $permissions, modified by the current umask, to set the
    permissions of the file.

  Ignored if the file already exists.
  */
  constructor.for_write path/string --permissions/int=((6 << 6) | (6 << 3) | 6):
    return Stream path (WRONLY | TRUNC | CREAT) permissions

  /**
  Opens the file at $path with the given $flags.

  The $flags parameter is a bitwise-or of the flags defined in this package,
    such as $RDONLY, $WRONLY, $RDWR, $APPEND, $CREAT, and $TRUNC.
  */
  constructor path/string flags/int:
    if (flags & CREAT) != 0:
      // Two argument version with no permissions can't create new files.
      throw "INVALID_ARGUMENT"
    return Stream path flags 0

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
    fd := null
    error := catch:
      fd = open_ path flags permissions
    if error:
      if error is string:
        throw "$error: \"$path\""
      throw error
    return Stream.internal_ fd

  /**
  Reads some data from the file, returning a byte array.
  Returns null on end-of-file.
  */
  read -> ByteArray?:
    return read_ fd_

  /**
  Writes part of the string or ByteArray to the open file descriptor.
  Returns the number of bytes written.
  */
  write data from/int=0 to/int=data.size -> int:
    return write_ fd_ data from to

  close -> none:
    close_ fd_

  is_a_terminal -> bool:
    return false


/// Deprecated. Use $read_content instead.
read_contents name:
  return read_content name

/**
Reads the content of a file.
The file must not change while it is read into memory.

# Advanced
The content is stored in an off-heap ByteArray.
On small devices with a flash filesystem, simply gets a view
  of the underlying bytes. (Not implemented yet)
*/
read_content file_name/string -> ByteArray:
  length := size file_name
  if length == 0: return ByteArray 0
  file := Stream.for_read file_name
  try:
    byte_array := file.read
    if not byte_array: throw "CHANGED_SIZE"
    if byte_array.size == length: return byte_array
    proxy := create_off_heap_byte_array length
    for pos := 0; pos < length; null:
      proxy.replace pos byte_array 0 byte_array.size
      pos += byte_array.size
      if pos == length: return proxy
      byte_array = file.read
      if not byte_array: throw "CHANGED_SIZE"
    return proxy
  finally:
    file.close

/**
Writes the given $content to a file of the given $path.
The file must not change while it is read into memory.

If $permissions is provided uses it to set the permissions of the file.
The $permissions are only used if the file is created, and not if it is
  overwritten.
*/
write_content content --path/string --permissions/int?=null -> none:
  stream := Stream.for_write path --permissions=permissions
  writer := Writer stream
  try:
    writer.write content
  finally:
    writer.close

// Path exists and is a file.
is_file name:
  stat := stat name
  if not stat: return false
  return stat[ST_TYPE] == REGULAR_FILE

// Path exists and is a directory.
is_directory name:
  stat := stat name
  if not stat: return false
  return stat[ST_TYPE] == DIRECTORY

// Return file size in bytes or null for no such file.
size name:
  stat := stat name
  if not stat: return null
  if stat[ST_TYPE] != REGULAR_FILE: throw "INVALID_ARGUMENT"
  return stat[ST_SIZE]

// Returns a file descriptor.  Only for use on actual files, not pipes,
// devices, etc.
open_ name flags permissions:
  #primitive.file.open

// Returns an array describing the given named entry in the filesystem, see the
// index names ST_DEV, etc.
stat name/string --follow_links/bool=true -> List?:
  #primitive.file.stat

// Takes an open file descriptor and determines if it represents a file
// as opposed to a socket or a pipe.
is_open_file_ fd:
  #primitive.file.is_open_file

// Reads some data from the file, returning a byte array.  Returns null on
// end-of-file.
read_ descriptor:
  #primitive.file.read

// Writes part of the string or ByteArray to the open file descriptor.
write_ descriptor data from to:
  #primitive.file.write

// Close open file
close_ descriptor:
  #primitive.file.close

// Delete a file, given its name.  Like 'rm' and the 'unlink()' system call,
// this only removes one hard link to a file. The file may still exist if there
// were other hard links.
delete name:
  #primitive.file.unlink

// Rename a file or directory. Only works if the new name is on the same
// filesystem.
rename from to:
  #primitive.file.rename
