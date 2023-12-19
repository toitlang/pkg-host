// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import reader show Reader
import writer show Writer

import system
import .directory

// Manipulation of files on a filesystem.
// Names work best when imported without "show *".

// Flags for file.Stream second constructor argument.  Analogous to the
// second argument to the open() system call.
RDONLY ::= 1
WRONLY ::= 2
RDWR ::= 3
APPEND ::= 4
CREAT ::= 8
TRUNC ::= 0x10

/// Index of the device number in the array returned by $stat.
ST_DEV ::= 0
/// Index of the inode number in the array returned by $stat.
ST_INO ::= 1
/// Index of the permissions bits in the array returned by $stat.
ST_MODE ::= 2
/// Index of the file type number in the array returned by $stat.
ST_TYPE ::= 3
/// Index of the link count in the array returned by $stat.
ST_NLINK ::= 4
/// Index of the owning user id in the array returned by $stat.
ST_UID ::= 5
/// Index of the owning group id in the array returned by $stat.
ST_GID ::= 6
/// Index of the file size in the array returned by $stat.
ST_SIZE ::= 7
/// Index of the last access time in the array returned by $stat.
ST_ATIME ::= 8
/// Index of the last modification time in the array returned by $stat.
ST_MTIME ::= 9
/// Index of the creation time in the array returned by $stat.
ST_CTIME ::= 10

/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a named FIFO.
FIFO ::= 0
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a character device.
CHARACTER_DEVICE ::= 1
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a directory.
DIRECTORY ::= 2
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a block device.
BLOCK_DEVICE ::= 3
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a regular file.
REGULAR_FILE ::= 4
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a symbolic link.
SYMBOLIC_LINK ::= 5
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a named socket.
SOCKET ::= 6
/**
The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a
  symlink to a directory. (Windows only).
*/
DIRECTORY_SYMBOLIC_LINK ::= 7

/**
An open file with a current position.  Corresponds in many ways to a file
  descriptor in Posix.
*/
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

/// Returns whether a path exists and is a regular file.
is_file name --follow_links/bool=true -> bool:
  stat := stat_ name follow_links
  if not stat: return false
  return stat[ST_TYPE] == REGULAR_FILE

/// Returns whether a path exists and is a directory.
is_directory name --follow_links/bool=true -> bool:
  stat := stat_ name follow_links
  if not stat: return false
  return stat[ST_TYPE] == DIRECTORY

/**
Returns the file size in bytes or null for no such file.
Throws an error if the name exists but is not a regular file.
*/
size name:
  stat := stat_ name true
  if not stat: return null
  if stat[ST_TYPE] != REGULAR_FILE: throw "INVALID_ARGUMENT"
  return stat[ST_SIZE]

// Returns a file descriptor.  Only for use on actual files, not pipes,
// devices, etc.
open_ name flags permissions:
  #primitive.file.open

/**
Returns an array describing the given named entry in the filesystem, see the
  index names $ST_DEV, etc.
*/
stat name/string --follow_links/bool=true -> List?:
  result := stat_ name follow_links
  if not result: return null
  result[ST_ATIME] = Time.epoch --ns=result[ST_ATIME]
  result[ST_MTIME] = Time.epoch --ns=result[ST_MTIME]
  result[ST_CTIME] = Time.epoch --ns=result[ST_CTIME]
  return result

stat_ name/string follow_links/bool -> List?:
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

/**
Deletes a file, given its name.
*/
delete name/string -> none:
  #primitive.file.unlink

/**
Renames a file or directory.
Only works if the $to name is on the same filesystem.
*/
rename from/string to/string -> none:
  #primitive.file.rename

/**
Creates a hard link from $source to a $target file.
*/
link --hard --source/string --target/string -> none:
  if not hard: throw "INVALID_ARGUMENT"
  link_ source target LINK_TYPE_HARD_

/**
Creates a soft link from $source to a $target file.
*/
link --file --source/string --target/string -> none:
  if not file: throw "INVALID_ARGUMENT"
  if is-directory target:
    throw "Target is a directory"
  link_ source target LINK_TYPE_SYMBOLIC_

/**
Creates a soft link from $source to a $target directory.
*/
link --directory --source/string --target/string -> none:
  if not directory: throw "INVALID_ARGUMENT"
  if is-file target:
    throw "Target is a file"
  if system.platform == system.PLATFORM-WINDOWS:
    link_ source target LINK_TYPE_SYMBOLIC_WINDOWS_DIRECTORY_
  else:
    link_ source target LINK_TYPE_SYMBOLIC_

/**
Creates a symbolic link from $source to $target. This version of link requires
  that the $target exists.
It will automatically choose the correct type of link (file or directory) based
  on the type of $target.
*/
link --source/string --target/string -> none:
  if not stat target: throw "INVALID_ARGUMENT"
  if is_directory target and system.platform == system.PLATFORM-WINDOWS:
    link_ source target LINK_TYPE_SYMBOLIC_WINDOWS_DIRECTORY_
  else:
    link_ source target LINK_TYPE_SYMBOLIC_

LINK_TYPE_HARD_                       ::= 0
LINK_TYPE_SYMBOLIC_                   ::= 1
LINK_TYPE_SYMBOLIC_WINDOWS_DIRECTORY_ ::= 2

link_ source/string target/string type/int -> none:
  #primitive.file.link

/**
Reads the destination of the link $name
*/
readlink name/string -> string:
  #primitive.file.readlink

/** Windows specific attribute for read-only files */
WINDOWS-FILE-ATTRIBUTE-READONLY ::= 0x01
/** Windows specific attribute for hidden files */
WINDOWS-FILE-ATTRIBUTE-HIDDEN   ::= 0x02
/** Windows specific attribute for system files */
WINDOWS-FILE-ATTRIBUTE-SYSTEM   ::= 0x04
/** Windows specific attribute for normal files */
WINDOWS-FILE-ATTRIBUTE-NORMAL   ::= 0x80
/** Windows specific attribute for archive files */
WINDOWS-FILE-ATTRIBUTE-ARCHIVE  ::= 0x20

/**
Changes filesystem permissions for the file $name to $permissions.
*/
chmod name/string permissions/int:
  #primitive.file.chmod
