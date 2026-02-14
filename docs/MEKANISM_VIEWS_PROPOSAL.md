# Mekanism Views Integration Proposal

## Overview

This proposal outlines the architecture for integrating Mekanism machines into ShelfOS views, supporting both single-machine-type displays and categorized multi-machine dashboards.

## Key Design Goals

1. **Multi-machine support** - Display all instances of one machine type
2. **Categorized display** - Show all machines grouped by category on large monitors
3. **Activity detection** - Accurately detect machine activity without `isBusy()` (Mekanism doesn't have this)
4. **Consistent architecture** - Follow existing patterns (AEInterface, BaseView, factories)

---

## Activity Detection Strategy

Mekanism machines don't expose `isBusy()`. Activity must be inferred per category:

### Processing Machines (Enrichment Chamber, Crusher, etc.)
```lua
-- Activity indicator: recipe progress > 0
local progress = machine.getRecipeProgress()
local total = machine.getTicksRequired()
local isActive = progress > 0 and total > 0
local progressPct = total > 0 and (progress / total * 100) or 0
```

### Generators (Solar, Wind, Heat, Bio, Gas)
```lua
-- Activity indicator: producing power
local production = machine.getProductionRate()
local isActive = production > 0
```

### Multiblocks (Boiler, Turbine, Fission, Fusion, SPS)
```lua
-- Activity indicator: formed + type-specific
local isFormed = machine.isFormed()
-- Then check type-specific activity:
-- Boiler: getBoilRate() > 0
-- Turbine: getProductionRate() > 0
-- Fission: getStatus() == true
-- Fusion: isIgnited() == true
```

### Storage (Dynamic Tank, QIO Drive Array)
```lua
-- Passive - show fill percentage
local pct = machine.getFilledPercentage()
```

---

## Proposed Architecture

### 1. MekanismInterface.lua (Peripheral Adapter)

Similar to `AEInterface.lua`, provides unified access to Mekanism machines.

```
mpm-packages/peripherals/MekanismInterface.lua
```

**Key Functions:**
```lua
MekanismInterface = {
    -- Discovery
    getMachineCategories()  -- Returns category definitions
    findMachines(category)  -- Find all machines in category
    findAllMachines()       -- Find all Mekanism machines

    -- Activity detection (normalized across types)
    isActive(machine)       -- Returns bool, activityData
    getActivityData(machine) -- Returns {active, progress, rate, etc.}

    -- Category info
    getCategory(peripheralType)  -- Map peripheral type to category
}
```

**Category Definitions:**
```lua
local CATEGORIES = {
    processing = {
        label = "Processing",
        types = {
            "enrichmentChamber", "crusher", "combiner",
            "metallurgicInfuser", "energizedSmelter", "precision_sawmill",
            -- factories
            "enrichingFactory", "crushingFactory", "sawingFactory", etc.
        },
        activityMethod = "getRecipeProgress"
    },
    generators = {
        label = "Generators",
        types = {
            "solarGenerator", "advancedSolarGenerator", "windGenerator",
            "heatGenerator", "bioGenerator", "gasBurningGenerator"
        },
        activityMethod = "getProductionRate"
    },
    multiblocks = {
        label = "Multiblocks",
        types = {
            "boilerValve", "turbineValve", "fissionReactorPort",
            "fusionReactorPort", "inductionPort", "spsPort"
        },
        activityMethod = "isFormed"  -- + type-specific secondary
    },
    storage = {
        label = "Storage",
        types = {
            "dynamicValve", "qioDriveArray", "bin", "fluidTank",
            "chemicalTank", "energyCube"
        },
        activityMethod = "getFilledPercentage"
    },
    logistics = {
        label = "Logistics",
        types = {
            "logisticalSorter", "digitalMiner", "qioExporter", "qioImporter"
        },
        activityMethod = nil  -- Custom per-type
    }
}
```

### 2. View Options

#### Option A: MekMachineStatus (Single Category View)
Replaces need to use generic `MachineStatus` for Mekanism machines.

**Config Schema:**
```lua
configSchema = {
    {
        key = "category",
        type = "select",
        label = "Category",
        options = function()
            return MekanismInterface.getMachineCategories()
        end
    },
    {
        key = "machine_type",
        type = "select",
        label = "Machine Type",
        options = function(config)
            return MekanismInterface.getMachineTypes(config.category)
        end,
        dependsOn = "category"
    }
}
```

**Display:** Grid of machines, color-coded by activity state.

#### Option B: MekDashboard (Categorized Overview)
Full dashboard showing all Mekanism machines grouped by category.

**Layout (Large Monitor):**
```
┌─────────────────────────────────────────────────────────────┐
│                    MEKANISM DASHBOARD                       │
├─────────────────────┬───────────────────┬───────────────────┤
│ PROCESSING (4/8)    │ GENERATORS (2/3)  │ MULTIBLOCKS       │
│ ┌────┐ ┌────┐      │ ┌────┐ ┌────┐    │ ┌────┐ ┌────┐    │
│ │EC 1│ │EC 2│      │ │SOLR│ │WIND│    │ │BOIL│ │TURB│    │
│ └────┘ └────┘      │ └────┘ └────┘    │ └────┘ └────┘    │
│ ┌────┐ ┌────┐      │ ┌────┐           │                   │
│ │CRSH│ │COMB│      │ │HEAT│           │                   │
│ └────┘ └────┘      │ └────┘           │                   │
├─────────────────────┴───────────────────┴───────────────────┤
│ STORAGE              │ LOGISTICS                            │
│ QIO: 45% | Tanks: 3  │ Miner: Active | Sorter: 2 running   │
└──────────────────────┴──────────────────────────────────────┘
```

**Layout (Small Monitor - Single Category Focus):**
```
┌───────────────────┐
│   PROCESSING      │
│  ┌────┐ ┌────┐   │
│  │ EC │ │CRSH│   │
│  │ 75%│ │idle│   │
│  └────┘ └────┘   │
│  4/8 active      │
└───────────────────┘
```

#### Option C: MekMachineGauge (Single Machine Monitor)
Deep single-machine view with detailed stats.

**Processing Machine Display:**
```
┌───────────────────────┐
│  ENRICHMENT CHAMBER   │
│  ████████░░ 80%       │
│                       │
│  Energy: 95%          │
│  Input:  Iron Ore x64 │
│  Output: Iron Dust    │
│                       │
│  Speed: 8 | Energy: 8 │
└───────────────────────┘
```

**Generator Display:**
```
┌───────────────────────┐
│   WIND GENERATOR      │
│       ⚡ 450 J/t      │
│                       │
│  Stored: 45%          │
│  Height: Y=128        │
│  Efficiency: 92%      │
└───────────────────────┘
```

---

## Implementation Plan

### Phase 1: Core Infrastructure
1. Create `MekanismInterface.lua`
   - Category definitions
   - Machine discovery (`peripheral.getNames()` + type filtering)
   - Activity detection per category
   - Data normalization

### Phase 2: MekMachineStatus View
1. Create `views/MekMachineStatus.lua`
   - Config: category + optional type filter
   - Grid display with activity indicators
   - Use `BaseView.custom()` pattern

### Phase 3: MekDashboard View
1. Create `views/MekDashboard.lua`
   - Auto-discover all Mekanism machines
   - Adaptive layout based on monitor size
   - Category grouping with summary stats

### Phase 4: MekMachineGauge View
1. Create `views/MekMachineGauge.lua`
   - Single machine deep-dive
   - Type-specific detail rendering
   - Config: peripheral name selection

---

## Peripheral Type Reference

### Processing Machines (have getRecipeProgress)
```
enrichmentChamber, crusher, combiner, metallurgicInfuser,
energizedSmelter, precisionSawmill, chemicalCrystallizer,
chemicalDissolutionChamber, chemicalInfuser, chemicalOxidizer,
chemicalWasher, rotaryCondensentrator, pressurizedReactionChamber,
electrolyticSeparator, isotopicCentrifuge, pigmentExtractor,
pigmentMixer, paintingMachine, nutritionalLiquifier
```

### Factory Machines (prefixed with tier)
```
basicEnrichingFactory, advancedEnrichingFactory, eliteEnrichingFactory, ultimateEnrichingFactory
basicCrushingFactory, advancedCrushingFactory, eliteCrushingFactory, ultimateCrushingFactory
(etc. for all factory types)
```

### Generators (have getProductionRate)
```
solarGenerator, advancedSolarGenerator, windGenerator,
heatGenerator, bioGenerator, gasBurningGenerator
```

### Multiblock Ports (have isFormed)
```
boilerValve, turbineValve, fissionReactorPort, fissionReactorLogicAdapter,
fusionReactorPort, fusionReactorLogicAdapter, inductionPort,
spsPort, dynamicValve, thermalEvaporationController
```

### Storage (have capacity methods)
```
bin, fluidTank, chemicalTank, energyCube, radioactiveWasteBarrel
```

### Logistics
```
logisticalSorter, digitalMiner, qioDriveArray, qioExporter,
qioImporter, qioDashboard, qioRedstoneAdapter
```

### Transmitters (tiered)
```
basicUniversalCable, advancedUniversalCable, eliteUniversalCable, ultimateUniversalCable
basicMechanicalPipe, advancedMechanicalPipe, eliteMechanicalPipe, ultimateMechanicalPipe
basicPressurizedTube, advancedPressurizedTube, elitePressurizedTube, ultimatePressurizedTube
```

---

## Color Coding Convention

| State | Color | Description |
|-------|-------|-------------|
| Active | `colors.green` | Machine processing/producing |
| Idle | `colors.gray` | Machine powered but not working |
| Error | `colors.red` | Machine has issue (waste full, etc.) |
| Offline | `colors.black` | Machine not formed/no power |
| Storage Full | `colors.yellow` | Near capacity |
| Storage Empty | `colors.lightGray` | Empty storage |

---

## Questions for User

1. **Priority**: Which view type should be implemented first?
   - MekMachineStatus (simple grid)
   - MekDashboard (categorized overview)
   - MekMachineGauge (single machine detail)

2. **Factory handling**: Should factories be shown as separate machines or grouped with their base type?

3. **Transmitter support**: Include cable/pipe monitoring or skip initially?

4. **Multiblock detail**: Show individual ports or aggregate to single multiblock status?
