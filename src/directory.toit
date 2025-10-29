// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

// Manipulation of directories on a filesystem.  Currently not available on
// embedded targets.  Names work best when imported with "show *".

import system
import .file as file

/**
The default directory separator for the underlying operating system.
*/
SEPARATOR/string ::= (system.platform == system.PLATFORM-WINDOWS) ? "\\" : "/"

/**
Removes an empty directory.

Throws a "FILE_NOT_FOUND" exception if the path does not exist or
  is not a directory.
*/
rmdir path/string -> none:
  #primitive.file.rmdir

/**
Removes the directory and all its content.

Does not follow symlinks, but removes the symlink itself.

If $force is true, also deletes files in read-only directories. This only
  has an effect when $recursive is set.

Throws a "FILE_NOT_FOUND" exception if the path does not exist or
  is not a directory.
*/
rmdir path/string --recursive/bool --force/bool=false -> none:
  if not recursive:
    rmdir path
    return
  dir-stat := file.stat --no-follow-links path
  if not dir-stat or dir-stat[file.ST-TYPE] != file.DIRECTORY:
    throw "FILE_NOT_FOUND"

  // A queue of directories to delete. Each entry is a pair of a path and a
  // boolean indicating whether the directory is known to be empty.
  queue := Deque
  queue.add [path, false]
  while not queue.is-empty:
    queue-entry := queue.last
    path = queue-entry[0]
    is-empty := queue-entry[1]
    if force:
      // Catch any exception in case we don't have the rights to change the
      // permissions. In that case we will fail when we need to delete a file later.
      catch:
        dir-stat = file.stat --no-follow-links path
        permissions := dir-stat[file.ST-MODE]
        if system.platform == system.PLATFORM-WINDOWS:
          if permissions & file.WINDOWS-FILE-ATTRIBUTE-READONLY != 0:
            file.chmod path (dir-stat[file.ST-MODE] & ~file.WINDOWS-FILE-ATTRIBUTE-READONLY)
        else:
          OWNER-READ-WRITE-SEARCH := 0b111_000_000
          if permissions & OWNER-READ-WRITE-SEARCH != OWNER-READ-WRITE-SEARCH:
            file.chmod path (dir-stat[file.ST-MODE] | OWNER-READ-WRITE-SEARCH)
    if not is-empty:
      is-empty = true
      stream := DirectoryStream path
      try:
        while entry := stream.next:
          child := "$path/$entry"
          type := (file.stat --no-follow-links child)[file.ST-TYPE]
          if type == file.DIRECTORY:
            queue.add [child, false]
            is-empty = false
          else if type == file.DIRECTORY-SYMBOLIC-LINK:
            // Windows special handling of symbolic links to a directory.
            // Note that the `rmdir` is not recursive.
            rmdir child
          else:
            file.delete child
      finally:
        stream.close
    if is-empty:
      queue.remove-last
      rmdir path
    else:
      // The next time we see this entry, we know it's empty, as
      // all children will have been removed.
      queue-entry[1] = true

/**
Creates an empty directory.

The given permissions are masked with the current umask to get
  the permissions of the new directory.
*/
mkdir path/string mode/int=0x1ff -> none:
  #primitive.file.mkdir

/**
Creates an empty directory, creating the parent directories if needed.

The given permissions are masked with the current umask to get
  the permissions of the new directory.
*/
mkdir --recursive/bool path/string mode/int=0x1ff -> none:
  if not recursive:
    mkdir path mode
    return

  // TODO(florian): This doesn't work for UNC drives on Windows.
  // We must not split the volume name.
  if system.platform == system.PLATFORM-WINDOWS:
    path = path.replace --all "\\" "/"

  built-path := ""
  parts := path.split "/"
  parts.size.repeat:
    part := parts[it]
    built-path += "$part"
    if part != "" and not file.is-directory built-path:
      mkdir built-path mode
    built-path += "/"

/**
Creates a fresh directory with the given prefix.

The system adds random characters to make the name unique and creates a fresh
  directory with the new name.
Returns the name of the created directory.

On Windows the prefix "/tmp/" is recognized, and the system's temporary
  directory is used, as returned by the Win32 API GetTempPath() call.

There is a hard-to-fix bug on Posix where a relative path is not handled
  correctly in the presence of calls to chdir.  The workaround is to use
  an absolute path like "/tmp/foo-".

# Examples
```
test_dir := mkdtemp "/tmp/test-"
print test_dir  // => "/tmp/test-1v42wp"  (for example).
```
*/
mkdtemp prefix/string="" -> string:
  return (mkdtemp_ prefix).to-string

mkdtemp_ prefix/string -> ByteArray:
  #primitive.file.mkdtemp

// Change the current directory.  Only changes the current directory for one
// Toit process, even if the Unix process contains more than one Toit process.
chdir name:
  #primitive.file.chdir

// An open directory, used to iterate over the named entries in a directory.
class DirectoryStream:
  dir_ := null
  is-closed_/bool := false

  constructor name:
    error := catch:
      dir_ = opendir_ resource-freeing-module_ name
    if error is string:
      throw "$error: \"$name\""
    else if error:
      throw error
    add-finalizer this:: dispose_

  /**
  Returns a string with the next name from the directory.
  The '.' and '..' entries are skipped and never returned.
  Returns null when no entries are left.
  */
  next -> string?:
    if is-closed_: throw "ALREADY_CLOSED"
    // We automatically dispose the underlying resource when
    // we reach the end of the stream. In that case, we return
    // null because we know that no more entries are left.
    dir := dir_
    if not dir: return null
    while true:
      bytes/ByteArray? := readdir_ dir
      if not bytes:
        dispose_
        return null
      str := bytes.to-string
      if str == "." or str == "..": continue
      return str

  close -> none:
    is-closed_ = true
    dispose_

  dispose_ -> none:
    dir := dir_
    if not dir: return
    dir_ = null
    closedir_ dir
    remove-finalizer this

opendir_ resource-group name:
  #primitive.file.opendir2

readdir_ directory -> ByteArray:
  #primitive.file.readdir

closedir_ directory:
  #primitive.file.closedir

same-entry_ a b:
  if a[file.ST-INO] != b[file.ST-INO]: return false
  return a[file.ST-DEV] == b[file.ST-DEV]

is-absolute_ path:
  if path.starts-with "/": return true
  if system.platform == system.PLATFORM-WINDOWS:
    if path.starts-with "//" or path.starts-with "\\\\": return true
    if path.size >= 3 and path[1] == ':': return true
  return false

// Get the canonical version of a file path, removing . and .. and resolving
// symbolic links.  Returns null if the path does not exist, but may throw on
// other errors such as symlink loops.
realpath path:
  if path is not string: throw "WRONG_TYPE"
  if path == "": throw "NO_SUCH_FILE"
  // Relative paths must be prepended with the current directory, and we can't
  // let the C realpath routine do that for us, because it doesn't understand
  // what our current directory is.
  if not is-absolute_ path:
    path = "$cwd/$path"
  #primitive.file.realpath

// Get the current working directory.  Like the 'pwd' command, this works by
// iterating up through the filesystem tree using the ".." links, until it
// finds the root.
cwd:
  #primitive.file.cwd:
    // The primitive is only implemented for Macos, so ending up here is normal.
    dir := ""
    pos := ""
    while true:
      dot := file.stat "$(pos)."
      dot-dot := file.stat "$(pos).."
      if same-entry_ dot dot-dot:
        return dir == "" ? "/" : dir
      found := false
      above := DirectoryStream "$(pos).."
      while name := above.next:
        name-stat := file.stat "$(pos)../$name" --follow-links=false
        if name-stat:
          if same-entry_ name-stat dot:
            dir = "/$name$dir"
            found = true
            break
      above.close
      pos = "../$pos"
      if not found:
        throw "CURRENT_DIRECTORY_UNLINKED"  // The current directory is not present in the file system any more.
