# Atom

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-1.0.0-green.svg)
![Status](https://img.shields.io/badge/status-experimental-orange)

A lightweight Roblox framework for declarative module loading and startup control.

## Features

- **Declarative Stages** - Control startup flow with a clean builder pattern
- **Remote Declarations** - Define and validate remotes in one place
- **Client Listeners** - Declarative server→client event handling
- **Zero Dependencies** - Single file, drop it in and go

## Installation

1. Download `Atom.luau`
2. Place it in `ReplicatedStorage`
3. Require it: `local Atom = require(ReplicatedStorage.Atom)`

## Quick Start

### Server
```lua
local Atom = require(ReplicatedStorage.Atom)

-- Register modules
Atom:AddChildren(ServerStorage.Systems)

-- Define startup stages
Atom:Stage("core")
    :Require("DataStore", "Stats")

Atom:Run()
```

### Module with Remotes
```lua
local Atom = require(ReplicatedStorage.Atom)

local Combat = Atom:Module({
    remotes = {
        CastSpell = Atom:Function({
            validate = function(player, spellName)
                return typeof(spellName) == "string"
            end
        })
    }
})

function Combat:CastSpell(player, spellName)
    print(player, "cast", spellName)
end

return Combat
```

### Client
```lua
local Atom = require(ReplicatedStorage.Atom)

Atom:AddChildren(script.Controllers)

-- Loading flow
Atom:Stage("loading")
    :Require("UIController", "Stats")
    :Await(function()
        return Atom:Get("Stats").loaded
    end)
    :Then(function()
        Atom:Get("UIController"):hideLoading()
    end)

Atom:Run()
```

### Client Listeners
```lua
local Atom = require(ReplicatedStorage.Atom)

local UI = Atom:Module({
    listeners = {
        ["CombatService.OnDamage"] = true, -- auto-binds to UI:OnDamage
        ["CombatService.UpdateHealth"] = function(health)
            print("Health:", health)
        end
    }
})

function UI:OnDamage(damage)
    print("Took damage:", damage)
end

return UI
```

### Calling Remotes (Client)
```lua
local Combat = Atom:GetRemotes("CombatService")
Combat.CastSpell:FireServer("fireball")
```

## API Reference

### Module Management

- `Atom:Add(module: ModuleScript)` - Register a module
- `Atom:AddModules(...: ModuleScript)` - Register multiple modules
- `Atom:AddChildren(parent: Instance)` - Register all ModuleScripts in parent
- `Atom:AddDescendants(parent: Instance)` - Register all descendant ModuleScripts

### Stages

- `Atom:Stage(name: string)` - Create a new stage
- `stage:Require(...: string)` - Require specific modules
- `stage:RequireAll()` - Require all registered modules
- `stage:Await(fn: () -> Signal)` - Wait for a signal
- `stage:Then(fn: () -> ())` - Run code after awaiting
- `Atom:Run()` - Execute all stages

*Stages aren't required, everything is automatically required after Run is called*

### Module Access

- `Atom:Get(name: string)` - Get a loaded module (errors if not loaded)
- `Atom:Await(name: string)` - Yield until module is loaded

### Remotes (Server)

- `Atom:Module(def)` - Define a module with remote definitions / custom name
- `Atom:Event(def)` - Create a RemoteEvent definition
- `Atom:Function(def)` - Create a RemoteFunction definition

### Remotes (Client)

- `Atom:GetRemotes(moduleName)` - Get remote folder for a module
- `Atom:Module(def)` - Define a module with listeners / custom name
