local function parse_edges(lines)
   local adj = {}
   local rev_adj = {}
   local nodes = {}

   local function add_node(name)
      if not nodes[name] then
         nodes[name] = true
         adj[name] = {}
         rev_adj[name] = {}
      end
   end

   for _, line in ipairs(lines) do
      line = line:gsub("^%s+", ""):gsub("%s+$", "")
      if #line == 0 then goto continue end

      local pkg, dep = line:match("^(.+)%s+>%s+(.+)$")
      if not pkg then goto continue end

      pkg = pkg:gsub("%s+$", "")
      dep = dep:gsub("^%s+", "")

      add_node(pkg)
      add_node(dep)

      table.insert(adj[dep], pkg)
      table.insert(rev_adj[pkg], dep)
      ::continue::
   end

   return adj, rev_adj, nodes
end

local function topological_sort(adj, rev_adj, nodes)
   local in_degree = {}
   local node_list = {}

   for name, _ in pairs(nodes) do
      in_degree[name] = #rev_adj[name]
      table.insert(node_list, name)
   end

   local queue = {}
   local qi, qj = 1, 0
   for _, name in ipairs(node_list) do
      if in_degree[name] == 0 then
         qj = qj + 1
         queue[qj] = name
      end
   end

   local result = {}
   while qi <= qj do
      local node = queue[qi]
      qi = qi + 1
      table.insert(result, node)

      for _, succ in ipairs(adj[node]) do
         in_degree[succ] = in_degree[succ] - 1
         if in_degree[succ] == 0 then
            qj = qj + 1
            queue[qj] = succ
         end
      end
   end

   if #result ~= #node_list then
      local remaining = {}
      for name, _ in pairs(nodes) do
         if in_degree[name] > 0 then
            table.insert(remaining, name)
         end
      end
      return nil, remaining
   end

   return result
end

local function resolve(input)
   local lines = {}
   for line in input:gmatch("[^\n]+") do
      table.insert(lines, line)
   end

   if #lines == 0 then
      return {}
   end

   local adj, rev_adj, nodes = parse_edges(lines)

   local order, cycle_nodes = topological_sort(adj, rev_adj, nodes)

   if not order then
      io.stderr:write("error: dependency cycle detected:\n")
      local cycle_str = table.concat(cycle_nodes, " -> ")
      io.stderr:write("  " .. cycle_str .. "\n")
      os.exit(1)
   end

   return order
end

local function main()
   local input

   if arg[1] then
      local f = io.open(arg[1], "r")
      if not f then
         io.stderr:write("error: cannot open file: " .. arg[1] .. "\n")
         os.exit(2)
      end
      input = f:read("*a")
      f:close()
   else
      input = io.stdin:read("*a")
   end

   if not input or #input == 0 then
      return
   end

   local order = resolve(input)

   for _, pkg in ipairs(order) do
      print(pkg)
   end
end

main()
