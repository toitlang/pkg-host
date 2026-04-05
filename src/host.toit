// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import encoding.json as json-codec
import encoding.yaml as yaml-codec
import io

import .file show
    is-file is-directory delete
    Stream
import .file as file

import .directory show
    mkdir rmdir mkdtemp
    chdir cwd realpath
    SEPARATOR
import .directory as directory

import .pipe show
    fork backticks run-program
    stdin stdout stderr
    exit-code exit-signal
    Process
import .pipe as pipe

import .os show
    env EnvironmentVariableMap

export is-file is-directory delete Stream
export mkdir rmdir mkdtemp chdir cwd realpath SEPARATOR
export fork backticks run-program stdin stdout stderr exit-code exit-signal Process
export env EnvironmentVariableMap

/**
Library for interacting with the host operating system.

Provides convenient access to file operations, directory management,
  process execution, and environment variables.

For less common operations, import the specific module directly:
- `import host.file` for $file.copy, $file.chmod, $file.rename,
  $file.link, $file.size, etc.
- `import host.pipe` for $pipe.to, $pipe.from, $pipe.system, etc.
- `import host.directory` for the low-level $directory.DirectoryStream.

# Examples

Read and write files:
```
import host

main:
  host.write "greeting.txt" --data="Hello, World!"
  content := host.read "greeting.txt"
  print content  // => Hello, World!
  host.delete "greeting.txt"
```

Read and write JSON:
```
import host

main:
  host.write --json "config.json" --data={"key": "value"}
  config := host.read --json "config.json"
  print config["key"]  // => value
```

Use temporary directories:
```
import host

main:
  host.with-tmp-directory: | tmp-dir |
    host.write "$tmp-dir/file.txt" --data="data"
    print (host.read "$tmp-dir/file.txt")
    // tmp-dir is cleaned up automatically.
```

Inspect files with $stat:
```
import host

main:
  info := host.stat "/etc/passwd"
  print info.size
  print info.modification-time
  print info.is-file         // => true
  print info.is-directory    // => false
```

List directory contents:
```
import host

main:
  entries := host.list-directory "/tmp"
  entries.do: print it

  // Or iterate directly with a block:
  host.list-directory "/tmp" --full-path: | path |
    print path  // => /tmp/some-entry
```

Run external programs:
```
import host

main:
  output := host.backticks "echo" "hello"
  print output  // => hello
```
*/


/**
Information about a file system entry.

Returned by $stat.
*/
class FileInfo:
  raw_/List

  constructor.from-raw_ .raw_:

  /** The device number of the file system containing this entry. */
  device -> int:
    return raw_[file.ST-DEV]

  /** The inode number. */
  inode -> int:
    return raw_[file.ST-INO]

  /**
  The permission bits of the file.

  On Windows this is a combination of Windows file attribute flags
    (see `host.file` for the constants).
  */
  mode -> int:
    return raw_[file.ST-MODE]

  /**
  The file type.

  One of the type constants defined in `host.file`, such as
    $file.REGULAR-FILE, $file.DIRECTORY, $file.SYMBOLIC-LINK, etc.

  For common cases, prefer the convenience methods $is-file,
    $is-directory, $is-symlink, etc.
  */
  type -> int:
    return raw_[file.ST-TYPE]

  /** The number of hard links to this entry. */
  link-count -> int:
    return raw_[file.ST-NLINK]

  /** The user id of the owner. */
  uid -> int:
    return raw_[file.ST-UID]

  /** The group id of the owner. */
  gid -> int:
    return raw_[file.ST-GID]

  /** The size in bytes. */
  size -> int:
    return raw_[file.ST-SIZE]

  /** The last access time. */
  access-time -> Time:
    return raw_[file.ST-ATIME]

  /** The last modification time. */
  modification-time -> Time:
    return raw_[file.ST-MTIME]

  /**
  The last status change time (Unix) or creation time (Windows).
  */
  change-time -> Time:
    return raw_[file.ST-CTIME]

  /** Whether this entry is a regular file. */
  is-file -> bool:
    return type == file.REGULAR-FILE

  /** Whether this entry is a directory. */
  is-directory -> bool:
    return type == file.DIRECTORY

  /**
  Whether this entry is a symbolic link.

  On Windows, also returns true for directory symbolic links.
  */
  is-symlink -> bool:
    return type == file.SYMBOLIC-LINK or type == file.DIRECTORY-SYMBOLIC-LINK

  /** Whether this entry is a block device. */
  is-block-device -> bool:
    return type == file.BLOCK-DEVICE

  /** Whether this entry is a character device. */
  is-character-device -> bool:
    return type == file.CHARACTER-DEVICE

  /** Whether this entry is a named pipe (FIFO). */
  is-pipe -> bool:
    return type == file.FIFO

  /** Whether this entry is a socket. */
  is-socket -> bool:
    return type == file.SOCKET

  /**
  Whether two $FileInfo objects refer to the same file system entry.

  Two entries are considered equal if they have the same device and
    inode numbers.
  */
  operator == other -> bool:
    if other is not FileInfo: return false
    return device == (other as FileInfo).device
        and inode == (other as FileInfo).inode

  hash-code -> int:
    return device * 31 + inode

  stringify -> string:
    type-str := ?
    if is-file: type-str = "file"
    else if is-directory: type-str = "directory"
    else if is-symlink: type-str = "symlink"
    else if is-block-device: type-str = "block-device"
    else if is-character-device: type-str = "character-device"
    else if is-pipe: type-str = "pipe"
    else if is-socket: type-str = "socket"
    else: type-str = "type=$type"
    return "FileInfo($type-str, size=$size)"

/**
Returns information about the given file system entry.

Returns null if the entry does not exist.

If $follow-links is true (the default), symbolic links are followed
  and the information is about the target of the link.
*/
stat name/string --follow-links/bool=true -> FileInfo?:
  result := file.stat name --follow-links=follow-links
  if not result: return null
  return FileInfo.from-raw_ result

/**
Reads the contents of the file at $path as a string.
*/
read path/string -> string:
  return (file.read-contents path).to-string

/**
Reads the contents of the file at $path as raw bytes.
*/
read --bytes path/string -> ByteArray:
  return file.read-contents path

/**
Reads the contents of the file at $path and parses it as JSON.

Uses streaming decoding, so the entire file does not need to be
  buffered in memory.
*/
read --json path/string -> any:
  stream := Stream.for-read path
  try:
    return json-codec.decode-stream stream.in
  finally:
    stream.close

/**
Reads the contents of the file at $path and parses it as YAML.
*/
read --yaml path/string -> any:
  return yaml-codec.decode (file.read-contents path)

/**
Writes the given $data to a file at $path.
*/
write path/string --data/io.Data -> none:
  file.write-contents data --path=path

/**
Serializes the given $data as JSON and writes it to a file at $path.

Uses streaming encoding, so the entire output does not need to be
  buffered in memory.
*/
write --json path/string --data -> none:
  stream := Stream.for-write path
  try:
    json-codec.encode-stream --writer=stream.out data
  finally:
    stream.close

/**
Serializes the given $data as YAML and writes it to a file at $path.
*/
write --yaml path/string --data -> none:
  file.write-contents (yaml-codec.encode data) --path=path

/**
Creates a temporary directory and calls the given $block with its path.

The directory is removed (recursively and forcefully) when the block
  returns or throws.

The $prefix is prepended to the generated directory name.

# Examples
```
import host

main:
  host.with-tmp-directory: | tmp-dir |
    host.write "$tmp-dir/test.txt" --data="data"
    // Directory is cleaned up here.
```
*/
with-tmp-directory prefix/string="" [block]:
  tmp-dir := mkdtemp prefix
  try:
    block.call tmp-dir
  finally:
    directory.rmdir tmp-dir --recursive --force

/**
Calls the given $block for each entry in the directory at $path.

The '.' and '..' entries are skipped.

If $full-path is true, each entry is prefixed with $path, yielding
  a complete path (for example, "/tmp/some-file" instead of just
  "some-file").
*/
list-directory path/string --full-path/bool=false [block] -> none:
  stream := directory.DirectoryStream path
  try:
    while entry := stream.next:
      if full-path: entry = "$path/$entry"
      block.call entry
  finally:
    stream.close

/**
Returns a list of entry names in the directory at $path.

The '.' and '..' entries are skipped.

If $full-path is true, each entry is prefixed with $path.

See also $(list-directory path [block]) for a streaming variant that
  does not allocate a list.
*/
list-directory path/string --full-path/bool=false -> List:
  result := []
  list-directory --full-path=full-path path: | entry | result.add entry
  return result
