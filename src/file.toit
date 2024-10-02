// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import reader as old-reader
import io

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
ST-DEV ::= 0
/// Index of the inode number in the array returned by $stat.
ST-INO ::= 1
/// Index of the permissions bits in the array returned by $stat.
ST-MODE ::= 2
/// Index of the file type number in the array returned by $stat.
ST-TYPE ::= 3
/// Index of the link count in the array returned by $stat.
ST-NLINK ::= 4
/// Index of the owning user id in the array returned by $stat.
ST-UID ::= 5
/// Index of the owning group id in the array returned by $stat.
ST-GID ::= 6
/// Index of the file size in the array returned by $stat.
ST-SIZE ::= 7
/// Index of the last access time in the array returned by $stat.
ST-ATIME ::= 8
/// Index of the last modification time in the array returned by $stat.
ST-MTIME ::= 9
/// Index of the creation time in the array returned by $stat.
ST-CTIME ::= 10

/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a named FIFO.
FIFO ::= 0
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a character device.
CHARACTER-DEVICE ::= 1
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a directory.
DIRECTORY ::= 2
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a block device.
BLOCK-DEVICE ::= 3
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a regular file.
REGULAR-FILE ::= 4
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a symbolic link.
SYMBOLIC-LINK ::= 5
/// The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a named socket.
SOCKET ::= 6
/**
The number for the ST_TYPE field of file.stat that indicates a filesystem entry that is a
  symlink to a directory. (Windows only).
*/
DIRECTORY-SYMBOLIC-LINK ::= 7

/**
An open file with a current position.  Corresponds in many ways to a file
  descriptor in Posix.
*/
class Stream extends Object with io.CloseableInMixin io.CloseableOutMixin implements old-reader.Reader:
  fd_ := ?

  constructor.internal_ .fd_:

  /**
  Opens the file at $path for reading.
  */
  constructor.for-read path/string:
    return Stream path RDONLY 0

  /**
  Opens the file at $path for writing.

  If the file does not exist, it is created.  If it exists, it is truncated.
  Uses the given $permissions, modified by the current umask, to set the
    permissions of the file.

  Ignored if the file already exists.
  */
  constructor.for-write path/string --permissions/int=((6 << 6) | (6 << 3) | 6):
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

  Deprecated. Use 'read' on $in instead.
  */
  read -> ByteArray?:
    return in.read

  read_ -> ByteArray?:
    return read-from-descriptor_ fd_

  /**
  Writes part of the string or ByteArray to the open file descriptor.
  Returns the number of bytes written.

  Deprecated. Use 'write' or 'try-write' on $out instead.
  */
  write data from/int=0 to/int=data.size -> int:
    return try-write_ data from to

  try-write_ data/io.Data from/int to/int -> int:
    return write-to-descriptor_ fd_ data from to

  close-reader_ -> none:
    close

  close-writer_ -> none:
    close

  close -> none:
    close_ fd_

  is-a-terminal -> bool:
    return false


/**
Use $read-contents instead.
*/
read-content name:
  return read-content name

/**
Reads the content of a file.
The file must not change while it is read into memory.

# Advanced
The content is stored in an off-heap ByteArray.
On small devices with a flash filesystem, simply gets a view
  of the underlying bytes. (Not implemented yet)
*/
read-contents file-name/string -> ByteArray:
  length := size file-name
  if length == 0: return #[]
  file := Stream.for-read file-name
  try:
    reader := file.in
    byte-array := reader.read
    if not byte-array: throw "CHANGED_SIZE"
    if byte-array.size == length: return byte-array
    proxy := create-off-heap-byte-array length
    for pos := 0; pos < length; null:
      proxy.replace pos byte-array 0 byte-array.size
      pos += byte-array.size
      if pos == length: return proxy
      byte-array = reader.read
      if not byte-array: throw "CHANGED_SIZE"
    return proxy
  finally:
    file.close

/** Use $write-contents instead. */
write-content content/io.Data --path/string --permissions/int?=null -> none:
  write-contents content --path=path --permissions=permissions

/**
Writes the given $content to a file of the given $path.
The file must not change while it is read into memory.

If $permissions is provided uses it to set the permissions of the file.
The $permissions are only used if the file is created, and not if it is
  overwritten.
*/
write-contents content/io.Data --path/string --permissions/int?=null -> none:
  stream := Stream.for-write path --permissions=permissions
  try:
    stream.out.write content
  finally:
    stream.close

/// Returns whether a path exists and is a regular file.
is-file name --follow-links/bool=true -> bool:
  stat := stat_ name follow-links
  if not stat: return false
  return stat[ST-TYPE] == REGULAR-FILE

/// Returns whether a path exists and is a directory.
is-directory name --follow-links/bool=true -> bool:
  stat := stat_ name follow-links
  if not stat: return false
  return stat[ST-TYPE] == DIRECTORY

/**
Returns the file size in bytes or null for no such file.
Throws an error if the name exists but is not a regular file.
*/
size name:
  stat := stat_ name true
  if not stat: return null
  if stat[ST-TYPE] != REGULAR-FILE: throw "INVALID_ARGUMENT"
  return stat[ST-SIZE]

// Returns a file descriptor.  Only for use on actual files, not pipes,
// devices, etc.
open_ name flags permissions:
  #primitive.file.open

/**
Returns an array describing the given named entry in the filesystem, see the
  index names $ST-DEV, etc.
*/
stat name/string --follow-links/bool=true -> List?:
  result := stat_ name follow-links
  if not result: return null
  result[ST-ATIME] = Time.epoch --ns=result[ST-ATIME]
  result[ST-MTIME] = Time.epoch --ns=result[ST-MTIME]
  result[ST-CTIME] = Time.epoch --ns=result[ST-CTIME]
  return result

stat_ name/string follow-links/bool -> List?:
  #primitive.file.stat

// Takes an open file descriptor and determines if it represents a file
// as opposed to a socket or a pipe.
is-open-file_ fd:
  #primitive.file.is-open-file

// Reads some data from the file, returning a byte array.  Returns null on
// end-of-file.
read-from-descriptor_ descriptor:
  #primitive.file.read

// Writes part of the io.Data to the open file descriptor.
write-to-descriptor_ descriptor data/io.Data from/int to/int:
  return #primitive.file.write: | error |
    written := 0
    io.primitive-redo-chunked-io-data_ error data from to: | chunk/ByteArray |
      chunk-written := write-to-descriptor_ descriptor chunk 0 chunk.size
      written += chunk-written
      if chunk-written < chunk.size: return written
    return written

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
link --hard/bool --source/string --target/string -> none:
  if not hard: throw "INVALID_ARGUMENT"
  link_ source target LINK-TYPE-HARD_

/**
Creates a soft link from $source to a $target file.
*/
link --file/bool --source/string --target/string -> none:
  if not file: throw "INVALID_ARGUMENT"
  if system.platform == system.PLATFORM-WINDOWS:
    // Work around https://github.com/toitlang/toit/issues/2090, where symbolic links with "/" don't work.
    // This still won't allow us to read symbolic links with '/' if they were created by other programs,
    // but at least we will be able to read the ones we create.
    target = target.replace --all "/" "\\"
  link_ source target LINK-TYPE-SYMBOLIC_

/**
Creates a soft link from $source to a $target directory.
*/
link --directory/bool --source/string --target/string -> none:
  if not directory: throw "INVALID_ARGUMENT"
  if system.platform == system.PLATFORM-WINDOWS:
    // Work around https://github.com/toitlang/toit/issues/2090, where symbolic links with "/" don't work.
    // This still won't allow us to read symbolic links with '/' if they were created by other programs,
    // but at least we will be able to read the ones we create.
    target = target.replace --all "/" "\\"
    link_ source target LINK-TYPE-SYMBOLIC-WINDOWS-DIRECTORY_
  else:
    link_ source target LINK-TYPE-SYMBOLIC_

/**
Creates a symbolic link from $source to $target. This version of link requires
  that the $target exists.
It will automatically choose the correct type of link (file or directory) based
  on the type of $target.
*/
link --source/string --target/string -> none:
  rooted-path := target
  if not is-rooted_ rooted-path:
    // We need to make the path relative to the source.
    rooted-path = "$(dirname_ source)/$target"
  if not stat rooted-path: throw "TARGET_NOT_FOUND"

  if system.platform == system.PLATFORM-WINDOWS:
    // Work around https://github.com/toitlang/toit/issues/2090, where symbolic links with "/" don't work.
    // This still won't allow us to read symbolic links with '/' if they were created by other programs,
    // but at least we will be able to read the ones we create.
    target = target.replace --all "/" "\\"

  if is-directory rooted-path and system.platform == system.PLATFORM-WINDOWS:
    link_ source target LINK-TYPE-SYMBOLIC-WINDOWS-DIRECTORY_
  else:
    link_ source target LINK-TYPE-SYMBOLIC_

LINK-TYPE-HARD_                       ::= 0
LINK-TYPE-SYMBOLIC_                   ::= 1
LINK-TYPE-SYMBOLIC-WINDOWS-DIRECTORY_ ::= 2

link_ source/string target/string type/int -> none:
  #primitive.file.link

/**
Reads the destination of the link $name
*/
readlink name/string -> string:
  #primitive.file.readlink

/** Windows specific attribute for read-only files. */
WINDOWS-FILE-ATTRIBUTE-READONLY  ::= 0x01
/** Windows specific attribute for hidden files. */
WINDOWS-FILE-ATTRIBUTE-HIDDEN    ::= 0x02
/** Windows specific attribute for system files. */
WINDOWS-FILE-ATTRIBUTE-SYSTEM    ::= 0x04
/** Windows specific attribute for sub directories. */
WINDOWS-FILE-ATTRIBUTE-DIRECTORY ::= 0x10
/** Windows specific attribute for archive files. */
WINDOWS-FILE-ATTRIBUTE-ARCHIVE   ::= 0x20
/** Windows specific attribute for normal files. */
WINDOWS-FILE-ATTRIBUTE-NORMAL    ::= 0x80

/**
Changes filesystem permissions for the file $name to $permissions.
*/
chmod name/string permissions/int:
  #primitive.file.chmod

/**
Copies $source to $target.

If $source is a file, then $target contains the copy and permissions of $source after
  the call.
If $source is a directory and $recursive is true, then $target contains the copy of
  the content of $source after the call. That is, all files that exist in $source
  will exist in $target after the call. The $target directory may exist.

The location (dirname) of $target must exist. That is, when copying to `foo/bar`, `foo`
  must exist.

If $dereference is true, then symbolic links are followed.

If $recursive is true, then directories are copied recursively. If $recursive is
  false, then $source must be a file.
*/
copy --source/string --target/string --dereference/bool=false --recursive/bool=false -> none:
  // A queue for pending recursive copies.
  queue := Deque

  copy_
      --source=source
      --target=target
      --dereference=dereference
      --recursive=recursive
      --queue=queue
      --allow-existing-target-directory
  while not queue.is-empty:
    next := queue.remove-first
    new-source := next[0]
    new-target := next[1]
    target-stat := stat new-target
    if not target-stat:
      throw "Target directory '$new-target' does not exist"
    target-permissions := target-stat[ST-MODE]
    is-windows := system.platform == system.PLATFORM-WINDOWS
    // If the The directory was marked as read-only.
    // Temporarily change the permissions to be able to copy the directory.
    OWNER-WRITE ::= 0b010_000_000
    if not is-windows and target-permissions & OWNER-WRITE != OWNER-WRITE:
      chmod new-target (target-permissions | OWNER-WRITE)
    else if is-windows and target-permissions & WINDOWS-FILE-ATTRIBUTE-READONLY != 0:
      // The directory was marked as read-only.
      // Temporarily change the permissions to be able to copy the directory.
      chmod new-target (target-permissions & ~WINDOWS-FILE-ATTRIBUTE-READONLY)
    else:
      // Mark as not needing any chmod.
      target-permissions = -1

    directory-stream := DirectoryStream new-source
    try:
      while entry := directory-stream.next:
        copy_
            --source="$new-source/$entry"
            --target="$new-target/$entry"
            --dereference=dereference
            --recursive=recursive
            --queue=queue
            --no-allow-existing-target-directory
    finally:
      directory-stream.close
      if target-permissions != -1:
        // Make the directory read-only again.
        chmod new-target target-permissions

SPECIAL-WINDOWS-PERMISSIONS_ ::= WINDOWS-FILE-ATTRIBUTE-READONLY | WINDOWS-FILE-ATTRIBUTE-HIDDEN

/**
Copies $source to $target.

The given $queue is filled with pending recursive copies. Each entry in the $queue
  is a pair of source, target, where both are directories that exist.
*/
copy_ -> none
    --source/string
    --target/string
    --dereference/bool
    --recursive/bool
    --queue/Deque
    --allow-existing-target-directory/bool:
  is-windows := system.platform == system.PLATFORM-WINDOWS

  source-stat := stat source --follow-links=dereference
  if not source-stat:
    throw "File/directory $source not found"
  source-permissions := source-stat[ST-MODE]
  type := source-stat[ST-TYPE]
  target-stat := stat target
  if target-stat and (type != DIRECTORY or not allow-existing-target-directory):
    throw "'$target' already exists"

  if type == SYMBOLIC-LINK or type == DIRECTORY-SYMBOLIC-LINK:
    // When taking the stat of the source we already declared whether we
    // dereference the link or not. If we are here, then we do not dereference
    // and should thus copy the link.
    link-target := readlink source
    if is-windows:
      // Work around https://github.com/toitlang/toit/issues/2090, where reading
      // an absolute symlink starts with '\??\' which Toit can't deal with if
      // written as value of a link.
      if link-target.starts-with "\\??\\": link-target = link-target[4..]
    link-type := type == DIRECTORY-SYMBOLIC-LINK
        ? LINK-TYPE-SYMBOLIC-WINDOWS-DIRECTORY_
        : LINK-TYPE-SYMBOLIC_
    link_ target link-target link-type
    return

  if type == DIRECTORY:
    if not recursive:
      throw "Cannot copy directory '$source' without --recursive"
    if not target-stat:
      mkdir target source-permissions
      if is-windows and source-permissions & SPECIAL-WINDOWS-PERMISSIONS_ != 0:
        // The Windows file attributes are not taken into account when creating a new directory.
        // Apply them now.
        chmod target source-permissions

    queue.add [source, target]
    return

  in-stream := Stream.for-read source
  out-stream := Stream.for-write target --permissions=source-permissions
  try:
    out-stream.out.write-from in-stream.in
  finally:
    in-stream.close
    out-stream.close
  if is-windows and (source-permissions & SPECIAL-WINDOWS-PERMISSIONS_) != 0:
    // The Windows file attributes are not taken into account when creating a new file.
    // Apply them now.
    chmod target source-permissions

/**
Returns the directory part of the given $path.
This is a simplified version of `dirname`, as it doesn't take into
  account complicated roots (specifically on Windows).

A complete version is in the 'fs' package.
*/
dirname_ path/string -> string:
  if path == "/": return "/"
  if path == "": return "."
  if path[path.size - 1] == '/': path = path[0..path.size - 2]
  last-separator := path.index-of --last "/"
  if system.platform == system.PLATFORM-WINDOWS:
    last-separator = max (path.index-of --last "\\") last-separator
  if last-separator == -1: return "."
  return path[0..last-separator]

/**
Returns the base name of the given $path.
This is a simplified version of `basename`, as it doesn't take into
  account complicated roots (specifically on Windows).

A complete version is in the 'fs' package.
*/
basename_ path/string -> string:
  if path == "/": return "/"
  if path == "": return "."
  if path[path.size - 1] == '/': path = path[0..path.size - 2]
  last-separator := path.index-of --last "/"
  if system.platform == system.PLATFORM-WINDOWS:
    last-separator = max (path.index-of --last "\\") last-separator
  if last-separator == -1: return path
  return path[last-separator + 1..]

is-volume-letter_ letter/int -> bool:
  return 'a' <= letter <= 'z' or 'A' <= letter <= 'Z'

/**
Returns whether the given $path is rooted.
On Linux and macOS, this means that the path is absolute.
On Windows this means that the path is absolute or starts with a volume letter,
  even if it isn't absolute (like `C:foo`).
*/
is-rooted_ path/string -> bool:
  if system.platform == system.PLATFORM-WINDOWS:
    if path.starts-with "\\" or path.starts-with "/": return true
    return path.size >= 2 and is-volume-letter_ path[0] and path[1] == ':'
  return path.starts-with "/"
