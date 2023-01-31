import host.os

// Expands environment variables in the arguments, using $ syntax.
main args:
  print
      (args.map: expand it).join " "

expand src -> string:
  dont_expand := true
  result := []
  src.split "\$": | part |
    if dont_expand:
      result.add part
      dont_expand = false
    else if part == "":
      result.add "\$"
      dont_expand = true
    else:
      var := part
      rest := ""
      close := part.index_of ")"
      if part[0] == '(' and close != -1:
        var = part[1..close]
        rest = part[close + 1 ..]
      else:
        for i := 0; i < part.size; i++:
          c := part[i]
          if not is_identifier c:
            var = part[0..i]
            rest = part[i..]
            break
      catch: result.add os.env[var]
      result.add rest
  return result.join ""

is_identifier c/int  -> bool:
  if 'a' <= c <= 'z': return true
  if 'A' <= c <= 'Z': return true
  if c == '_': return true
  return '0' <= c <= '9'
