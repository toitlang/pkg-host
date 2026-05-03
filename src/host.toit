// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import encoding.json as json-codec
import encoding.yaml as yaml-codec
import io

import .file show
    is-file is-directory find-executable
    Stream
import .file as file

import .directory show
    mkdir rmdir
    chdir cwd realpath
import .directory as directory

import .pipe show
    stdin stdout stderr print-to-stderr
    Process
import .pipe as pipe

import .os show
    env EnvironmentVariableMap

export is-file is-directory find-executable
export mkdir rmdir chdir cwd realpath
export stdin stdout stderr print-to-stderr Process
export env EnvironmentVariableMap

/**
Library for interacting with the host operating system.

Provides convenient access to file operations, directory management,
  process execution, and environment variables.

For less common operations, import the specific module directly:
- `import host.file` for $file.copy, $file.chmod, $file.rename,
  $file.link, $file.size, $file.Stream (streaming I/O), etc.
- `import host.pipe` for $pipe.fork, $pipe.backticks, $pipe.run-program,
  $pipe.to, $pipe.from, $pipe.system, etc.
- `import host.directory` for $directory.mkdtemp and the low-level
  $directory.DirectoryStream.

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

Run an external program and capture its stdout:
```
import host

main:
  output := host.run "echo" "hello"
  print output  // => "hello\n"
```

Start a process asynchronously and wait for it to finish:
```
import host

main:
  process := host.start-process "sleep" ["1"]
  process.wait
  if process.exit-signal:
    print "killed by signal $process.exit-signal"
  else:
    print "exit code: $process.exit-code"
```

Delete a directory tree:
```
import host

main:
  host.delete "build" --recursive --force
```
*/

/**
The default directory separator for the underlying operating system.

On POSIX systems this is forward slash; on Windows it is backslash.
*/
DIRECTORY-SEPARATOR/string ::= directory.SEPARATOR

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
Deletes the file or directory at $path.

For files, $recursive and $force are ignored.

For directories, $recursive must be true unless the directory is
  already empty (otherwise the underlying $directory.rmdir would
  throw). With $force, files inside read-only directories are also
  removed; this only takes effect together with $recursive.

Throws if $path does not exist.
*/
delete path/string --recursive/bool=false --force/bool=false -> none:
  info := stat path --follow-links=false
  if not info: throw "FILE_NOT_FOUND"
  if info.is-directory:
    directory.rmdir path --recursive=recursive --force=force
  else:
    file.delete path

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
  tmp-dir := directory.mkdtemp prefix
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

/**
Starts an external program as a child process.

Looks up $command on the PATH (unless $use-path is false) and runs it,
  passing the given $arguments. The child's argv list is built as
  $command followed by $arguments — callers do not need to repeat
  $command at the front of $arguments. Returns a $Process handle that
  can be used to access the child's standard streams, wait for
  completion, or query the exit status.

To avoid leaving a zombie, eventually call $Process.wait or
  $Process.wait-ignore.

Attaches the given $stdin, $stdout, $stderr streams to the corresponding
  streams of the child process. If a stream is null, then it is inherited.
  Use $(Stream.constructor --parent-to-child) or
  $(Stream.constructor --child-to-parent) to create a fresh pipe.
Alternatively, a pipe can be created using the $create-stdin,
  $create-stdout, and $create-stderr flags. In this case use $Process.stdin,
  $Process.stdout, and $Process.stderr to access the streams.
The $stdin and $create-stdin (respectively $stdout and $create-stdout,
  $stderr and $create-stderr) arguments are mutually exclusive.

The $file-descriptor-3 and $file-descriptor-4 can be used to pass streams
  as open file descriptors 3 and/or 4 to the child process.

The $environment variable, if given, must be a map where the keys are strings
  and the values strings or null, where null indicates that the variable
  should be unset in the child process.

If you override the PATH environment variable, but set the $use-path flag,
  the new value of PATH will be used to find the executable.

# Examples
```
import host

main:
  process := host.start-process "echo" ["hi"] --create-stdout
  data := process.stdout.in.read-all
  process.wait
  print data.to-string  // => "hi\n"
```
*/
start-process command/string arguments/List -> Process
    --use-path/bool=true
    --environment/Map?=null
    --stdin/Stream?=null
    --stdout/Stream?=null
    --stderr/Stream?=null
    --create-stdin/bool=false
    --create-stdout/bool=false
    --create-stderr/bool=false
    --file-descriptor-3/Stream?=null
    --file-descriptor-4/Stream?=null:
  argv := List arguments.size + 1
  argv[0] = command
  arguments.size.repeat: argv[it + 1] = arguments[it]
  return pipe.fork command argv
      --use-path=use-path
      --environment=environment
      --stdin=stdin
      --stdout=stdout
      --stderr=stderr
      --create-stdin=create-stdin
      --create-stdout=create-stdout
      --create-stderr=create-stderr
      --file-descriptor-3=file-descriptor-3
      --file-descriptor-4=file-descriptor-4

/// Variant of $(run arguments).
run --environment/Map?=null command/string arg1/string -> string:
  return pipe.backticks --environment=environment [command, arg1]

/// Variant of $(run arguments).
run --environment/Map?=null command/string arg1/string arg2/string -> string:
  return pipe.backticks --environment=environment [command, arg1, arg2]

/// Variant of $(run arguments).
run --environment/Map?=null command/string arg1/string arg2/string arg3/string -> string:
  return pipe.backticks --environment=environment [command, arg1, arg2, arg3]

/// Variant of $(run arguments).
run --environment/Map?=null command/string arg1/string arg2/string arg3/string arg4/string -> string:
  return pipe.backticks --environment=environment [command, arg1, arg2, arg3, arg4]

/**
Runs an external program and returns its captured stdout.

Looks up the command on the PATH and runs it. The captured stdout is
  returned as a string when the process finishes.

Can be passed either a command (with no arguments) as a string, or a list
  of arguments where the 0th argument is the command.

Throws if the program exits with a non-zero exit code or because of a signal.

The $environment argument is used as in $start-process.

# Examples
```
import host

main:
  output := host.run "echo" "hello"
  print output  // => "hello\n"
```
*/
run --environment/Map?=null arguments -> string:
  return pipe.backticks --environment=environment arguments
