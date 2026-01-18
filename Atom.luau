local RunService = game:GetService("RunService")

local Atom = {}

local modules = {}
local loaded = {}
local stages = {}
local yielded = {}

local Event = {}
local Function = {}

type BaseRemoteDef = {
	validate: ((Player, ...any) -> boolean)?,
	handler: ((Player, ...any) -> ...any)?,
	direction: ("Server" | "Client")?,
}

type EventDef = BaseRemoteDef & {
	reliable: boolean?,
}

type FunctionDef = BaseRemoteDef

type RemoteDef = EventDef | FunctionDef
type ListenerDef = true | (...any) -> any

type ModuleDef = {
	name: string?,
	remotes: { [string]: RemoteDef }?,
	listeners: { [string]: ListenerDef }?,
}

type Module = {
	name: string,
	remotes: { [string]: RemoteEvent | UnreliableRemoteEvent | RemoteFunction }?,
	[any]: any,
}

type Stage = {
	Require: (...string) -> Stage,
	RequireAll: () -> Stage,
	Await: (() -> { Wait: () -> () }) -> Stage,
	Then: () -> Stage,
}

local function buildRemotes(module)
	local remoteFolder = script:FindFirstChild("Remotes")
	if not remoteFolder then
		remoteFolder = Instance.new("Folder")
		remoteFolder.Name = "Remotes"
		remoteFolder.Parent = script
	end

	local folder = Instance.new("Folder")
	folder.Name = module.name
	folder.Parent = remoteFolder

	for name, def in module.remotes do
		local mt = getmetatable(def)
		local remote

		if mt == Event then
			remote = def.reliable and Instance.new("RemoteEvent") or Instance.new("UnreliableRemoteEvent")
		elseif mt == Function then
			remote = Instance.new("RemoteFunction")
		end

		remote.Name = name
		remote.Parent = folder
		def.remote = remote

		module._remoteDefs[name] = def
		module.remotes[name] = remote
	end
end

local function connectRemotes(module)
	for name, def in module._remoteDefs do
		local mt = getmetatable(def)
		local remote = def.remote
		local direction = def.direction
		local handler = def.handler or module[name]

		if direction == "Client" then
			continue
		end

		if mt == Event then
			remote.OnServerEvent:Connect(function(player, ...)
				if typeof(def.validate) == "function" and not def.validate(player, ...) then
					return
				end
				handler(module, player, ...)
			end)
		elseif mt == Function then
			remote.OnServerInvoke = function(player, ...)
				if typeof(def.validate) == "function" and not def.validate(player, ...) then
					return
				end
				return handler(module, player, ...)
			end
		end
	end
end

local function getRemote(moduleName, remoteName)
	local moduleFolder = Atom:GetRemotes(moduleName)

	local remote = moduleFolder:WaitForChild(remoteName, 10)
	assert(remote, `Remote "{remoteName}" not found`)

	return remote
end

local function connectListeners(module)
	for key, handler in module.listeners do
		local moduleName, remoteName = string.match(key :: string, "^(.+)%.(.+)$")
		assert(moduleName and remoteName, `Invalid listener key: {key}`)

		if handler == true then
			handler = module[remoteName] :: (...any) -> any
		end

		assert(typeof(handler) == "function", `No handler for {key}`)

		local remote = getRemote(moduleName, remoteName)

		if remote:IsA("RemoteFunction") then
			remote.OnClientInvoke = handler
		else
			remote.OnClientEvent:Connect(handler)
		end
	end
end

local function wake(module)
	if yielded[module.name] then
		for _, co in yielded[module.name] do
			coroutine.resume(co, module)
		end
	end
end

local function requireAsync(moduleScript)
	if loaded[moduleScript.Name] then
		return
	end

	task.spawn(function()
		local module = require(moduleScript)
		module.name = module.name or moduleScript.Name
		loaded[module.name] = module

		if RunService:IsServer() then
			if module.remotes then
				connectRemotes(module)
			end
		elseif RunService:IsClient() then
			if module.listeners then
				connectListeners(module)
			end
		end

		wake(module)

		return module
	end)
end

function Atom:Event(def: EventDef): RemoteEvent | UnreliableRemoteEvent
	def = def or {}
	def.reliable = def.reliable ~= false
	def.direction = def.direction or "Server"
	return setmetatable(def, Event)
end

function Atom:Function(def: FunctionDef): RemoteFunction
	def = def or {}
	def.direction = def.direction or "Server"
	return setmetatable(def, Function)
end

function Atom:Module(def: ModuleDef?): Module
	def = def or {}
	def.name = def.name or string.match(debug.info(2, "s"), "([^.]+)$")

	if RunService:IsServer() then
		if def.remotes then
			def._remoteDefs = {}
			buildRemotes(def)
		end
	end

	return def
end

function Atom:GetRemotes(moduleName: string): Folder
	local remoteFolder = script:WaitForChild("Remotes", 10)
	assert(remoteFolder, "Remote folder not found")

	local moduleFolder = remoteFolder:WaitForChild(moduleName, 10)
	assert(moduleFolder, `Module folder "{moduleName}" not found`)

	return moduleFolder
end

function Atom:Add(module: ModuleScript)
	assert(module:IsA("ModuleScript"), `Expected ModuleScript, got {module.ClassName}`)
	assert(not modules[module.Name], `Module "{module.Name}" already exists`)
	if string.match(module.Name, "^_") then
		warn("Skipping private module: ", module.Name)
		return
	end

	modules[module.Name] = module
end

function Atom:AddModules(...: ModuleScript)
	for _, module in { ... } do
		self:Add(module)
	end
end

function Atom:AddChildren(parent: Instance)
	assert(typeof(parent) == "Instance", "Atom:AddAll expects parent to be an Instance")

	for _, module in parent:GetChildren() do
		if module:IsA("ModuleScript") then
			self:Add(module)
		end
	end
end

function Atom:AddDescendants(parent: Instance)
	assert(typeof(parent) == "Instance", "Atom:AddAll expects parent to be an Instance")

	for _, module in parent:GetDescendants() do
		if module:IsA("ModuleScript") then
			self:Add(module)
		end
	end
end

function Atom:Get(name: string): Module
	assert(modules[name]:GetFullName() ~= debug.info(2, "s"), "Cannot get self")
	return assert(loaded[name], `No module named "{name}" found`)
end

function Atom:Await(name: string): Module
	if loaded[name] then
		return loaded[name]
	end

	local running = coroutine.running()
	assert(running ~= nil, "Cannot await on the main thread")

	yielded[name] = yielded[name] or {}
	table.insert(yielded[name], running)
	return coroutine.yield()
end

function Atom:Run()
	for _, stage in stages do
		for _, step in stage._steps do
			if step.type == "require" then
				for _, moduleName in step.requires do
					local module = modules[moduleName]
					assert(module, `Cannot require module "{module}" - module doesn't exist, consider awaiting it`)

					requireAsync(module)
				end
			elseif step.type == "requireAll" then
				for _, module in modules do
					requireAsync(module)
				end
			elseif step.type == "await" then
				local signal = step.getSignal()
				assert(typeof(signal.Wait) == "function", "Cannot await signal, no :Wait found")

				signal:Wait()
			elseif step.type == "then" then
				step.fn()
			end
		end
	end

	for _, module in modules do
		requireAsync(module)
	end
end

function Atom:Stage(name: string): Stage
	local stage = {
		_name = name,
		_steps = {},
	}

	function stage.Require(_, ...): Stage
		table.insert(stage._steps, {
			type = "require",
			requires = { ... },
		})

		return stage
	end

	function stage.RequireAll(): Stage
		table.insert(stage._steps, {
			type = "requireAll",
		})

		return stage
	end

	function stage.Await(_, fn): Stage
		table.insert(stage._steps, {
			type = "await",
			getSignal = fn,
		})

		return stage
	end

	function stage.Then(_, fn): Stage
		table.insert(stage._steps, {
			type = "then",
			fn = fn,
		})

		return stage
	end

	table.insert(stages, stage)
	return stage
end

return Atom
