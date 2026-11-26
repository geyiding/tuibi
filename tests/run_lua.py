"""用 lupa（Lua 5.4）运行 tests/*.lua（UTF-8 searcher 兼容中文目录）"""
import os
import sys
from lupa import lua54

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = lua54.LuaRuntime(unpack_returned_tuples=True)

search_roots = [
    os.path.join(root, "scripts"),
    os.path.join(root, "tests"),
    os.path.join(root, "tests", "stubs"),
]

def read_lua_module(mod_name):
    rel = mod_name.replace(".", "/") + ".lua"
    for base in search_roots:
        full = os.path.join(base, rel)
        if os.path.isfile(full):
            with open(full, "r", encoding="utf-8") as f:
                return f.read(), full
    return None, None

setup = L.eval(
    """
    function(reader, m, a)
        MAIN_PATH = m
        ASSETS_PATH = a
        table.insert(package.searchers, 2, function(name)
            local src, full = reader(name)
            if not src then return "\\n\\tno utf8 file for " .. tostring(name) end
            local fn, err = load(src, "@" .. full)
            if not fn then error(err) end
            return fn
        end)
    end
    """
)
setup(read_lua_module, os.path.join(root, "scripts", "main.lua"), os.path.join(root, "assets"))

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as f:
        src = f.read()
    fn = L.eval(
        "function(src, name) local f, e = load(src, '@' .. name); if not f then error(e) end; return f() end"
    )
    fn(src, path)
