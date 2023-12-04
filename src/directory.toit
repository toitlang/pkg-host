// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

// Manipulation of directories on a filesystem.  Currently not available on
// embedded targets.  Names work best when imported with "show *".

import system
import .file as file

/**
The dir separator for the underlying operating system.
*/
directory-separator -> string:
  if system.platform == system.PLATFORM-WINDOWS:
    return "\\"
  else:
    return "/"

/** Removes an empty directory. */
rmdir path/string -> none:
  #primitive.file.rmdir

/**
Removes the directory and all its content.

Does not follow symlinks, but removes the symlink itself.
*/
rmdir path/string --recursive/bool -> none:
  if not recursive:
    rmdir path
    return
  stream := DirectoryStream path
  while entry := stream.next:
    child := "$path/$entry"
    type := (file.stat --no-follow_links child)[file.ST_TYPE]
    if type == file.DIRECTORY:
      rmdir --recursive child
    else if type == file.DIRECTORY_SYMBOLIC_LINK:
      rmdir child // Windows special handling of symbolic links to a directory
    else:
      file.delete child
  stream.close
  rmdir path

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

  built_path := ""
  parts := path.split "/"
  parts.size.repeat:
    part := parts[it]
    built_path += "$part"
    if part != "" and not file.is_directory built_path:
      mkdir built_path mode
    built_path += "/"

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
  return (mkdtemp_ prefix).to_string

mkdtemp_ prefix/string -> ByteArray:
  #primitive.file.mkdtemp

// Change the current directory.  Only changes the current directory for one
// Toit process, even if the Unix process contains more than one Toit process.
chdir name:
  #primitive.file.chdir

// An open directory, used to iterate over the named entries in a directory.
class DirectoryStream:
  dir_ := null
  is_closed_/bool := false

  constructor name:
    error := catch:
      dir_ = opendir_ resource_freeing_module_ name
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
    if is_closed_: throw "ALREADY_CLOSED"
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
      str := bytes.to_string
      if str == "." or str == "..": continue
      return str

  close -> none:
    is_closed_ = true
    dispose_

  dispose_ -> none:
    dir := dir_
    if not dir: return
    dir_ = null
    closedir_ dir
    remove_finalizer this

opendir_ resource_group name:
  #primitive.file.opendir2

readdir_ dir -> ByteArray:
  #primitive.file.readdir

closedir_ dir:
  #primitive.file.closedir

same_entry_ a b:
  if a[file.ST_INO] != b[file.ST_INO]: return false
  return a[file.ST_DEV] == b[file.ST_DEV]

is_absolute_ path:
  if path.starts_with "/": return true
  if system.platform == system.PLATFORM_WINDOWS:
    if path.starts_with "//" or path.starts_with "\\\\": return true
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
  if not is_absolute_ path:
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
      dot_dot := file.stat "$(pos).."
      if same_entry_ dot dot_dot:
        return dir == "" ? "/" : dir
      found := false
      above := DirectoryStream "$(pos).."
      while name := above.next:
        name_stat := file.stat "$(pos)../$name" --follow_links=false
        if name_stat:
          if same_entry_ name_stat dot:
            dir = "/$name$dir"
            found = true
            break
      above.close
      pos = "../$pos"
      if not found:
        throw "CURRENT_DIRECTORY_UNLINKED"  // The current directory is not present in the file system any more.
