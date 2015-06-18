local lfs = require 'lfs'

if _VERSION == 'Lua 5.2' then
  unpack = table.unpack
end

local saveRBXM do
  -- because of the way XML is parsed, leading spaces get truncated
  -- so, simply add a "\" when a space or "\" is detected as the first character
  -- this will be decoded automatically by Cure
  local function encodeTruncEsc(str)
    local first = str:sub(1,1)
    if first:match('%s') or first == [[\]] then
      return [[\]] .. str
    end
    return str
  end

  local function escapeToXML(str)
    local nameEsc = {
      ['"'] = "quot";
      ["&"] = "amp";
      ["'"] = "apos";
      ["<"] = "lt";
      [">"] = "gt";
    }
    local out = ""
    for i = 1,#str do
      local c = str:sub(i,i)
      if nameEsc[c] then
        c = "&" .. nameEsc[c] .. ";"
      elseif not c:match("^[\10\13\32-\126]$") then
        c = "&#" .. c:byte() .. ";"
      end
      out = out .. c
    end
    return out
  end

  local encodeDataType = {
    ['string'] = function(data)
      return encodeTruncEsc(escapeToXML(data))
    end;
    ['ProtectedString'] = function(data)
      return encodeTruncEsc(escapeToXML(data))
    end;
  }

  -- Converts a RBXM table to a string.
  local function strRBXM(var)
    if type(var) ~= 'table' then
      error("table expected",2)
    end

    local contentString = {}
    local function output(...)
      local args = {...}
      for i = 1,#args do
        if type(args[i]) == 'table' then
          output(unpack(args[i]))
        else
          contentString[#contentString+1] = tostring(args[i])
        end
      end
    end

    local tab do
      local t = 1
      function tab(n)
        if n then t = t + n end
        return string.rep("\t",t)
      end
    end

    local ref = 0
    local function r(object)
      output("\n",tab(),[[<Item class="]],object.ClassName,[[" referent="RBX]],ref,[[">]],"\n",tab(1),[[<Properties>]])
      ref = ref + 1

      local sorted = {}
      for k in pairs(object) do
        if type(k) == 'string' and k ~= "ClassName" then
          sorted[#sorted+1] = k
        end
      end
      table.sort(sorted)
      tab(1)
      for i = 1,#sorted do
        local propName = sorted[i]
        local propType,propValue = object[propName][1],object[propName][2]

        if encodeDataType[propType] then
          propValue = encodeDataType[propType](propValue,tab)
        end

        output("\n",tab(),[[<]],propType,[[ name="]],propName,[[">]],propValue,[[</]],propType,[[>]])
      end
      output("\n",tab(-1),[[</Properties>]])

      for i = 1,#object do
        r(object[i])
      end

      output("\n",tab(-1),[[</Item>]])
    end

    output(
      [[<roblox ]],
      [[xmlns:xmime="http://www.w3.org/2005/05/xmlmime" ]],
      [[xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ]],
      [[xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" ]],
      [[version="4">]]
    )
    r(var)
    output("\n</roblox>")
    return table.concat(contentString)
  end

  -- Saves a RBXM string or table.
  function saveRBXM(var,filename)
    if type(var) == 'table' then
      var = strRBXM(var)
    end
    if type(var) == 'string' then
      local file = assert(io.open(filename,'w'))
      file:write(var)
      file:flush()
      file:close()
    else
      error("bad type",2)
    end
  end
end

local function splitName(path)
  for i = #path,1,-1 do
    local c = path:sub(i,i)
    if c == "." then
      return path:sub(1,i-1),path:sub(i+1,#path)
    end
  end
  return path,""
end

local function checkSyntax(source)
  -- If it's a script, you want to make sure it can compile!
  local f, e = loadstring(source,'')
  if not f then
    print("WARNING: " .. e:gsub('^%[.-%]:',"line "))
  end
end

local function handleFile(path,file,sub)
  local content do
    local f = assert(io.open(path))
    content = f:read('*a')
    f:close()
  end

  local name,ext = splitName(file)
  ext = ext:lower()
  if ext == "lua" then
    checkSyntax(content)
    local subname,subext = splitName(name)
    if subext:lower() == "script" then
      return {
          ClassName='Script';
          Name={'string',subname};
          Source={'ProtectedString',content};
      }
    elseif subext:lower() == "localscript" then
      return {
          ClassName='LocalScript';
          Name={'string',subname};
          Source={'ProtectedString',content};
      }
    elseif subext:lower() == "modulescript" then
      return {
          ClassName='ModuleScript';
          Name={'string',subname};
          Source={'ProtectedString',contentg};
      }
    elseif subext == "" then
      print(string.format("WARNING: %s has no subextension", path))
    else
      print(string.format("WARNING: %s has an unrecognized subextension", path))
    end
  else
    print(string.format("WARNING: %s has an unrecognized extension", path))
  end
end

local function recurseDir(path,obj,r)
  print("DIR ",path)
  for name in lfs.dir(path) do
    if name ~= ".." and name ~= "." and name ~= ".gitignore" then
      local p = path .. "/" .. name
      if lfs.attributes(p,'mode') == 'directory' then
        obj[#obj+1] = recurseDir(p,{ClassName='Configuration', Name={'string',name}},true)
      else
        print("FILE",p)
        obj[#obj+1] = handleFile(p,name,r)
      end
    end
  end
  return obj
end

local rbxmObj = recurseDir("source",{ClassName='Configuration', Name={'string',"cure"}})
saveRBXM(rbxmObj,"build/" .. ((...) or "cure.rbxm"))
