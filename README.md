# SAFE MODE

A co-op survival-horror game that takes place **inside a PC**. You and up to four
others drop into the machine as first-person "processes" and hunt down a physical
infection — the malware is a *thing* that walks the corridors, not a menu you click.
Purge every corruption growth before it finds you. There's a **solo mode**, because
nobody has to come with you.

The horror is meant to be **subtle and liminal**: mundane, true-sounding lines of
text that are wrong in a way you feel a second late; lights that drop out for no
reason; a monster that gets closer only when you aren't looking at it.

- **Engine:** Godot 4.7+ (renders through **Metal** on macOS; Vulkan/D3D12 on
  Windows; OpenGL on web/ChromeOS).
- **Players:** 1 (solo) to 5 (co-op, LAN/host-join) with **proximity voice chat**.
- **Look:** PS1-era analog horror — low geometry, dark PCB-green materials, glowing
  circuit traces, and a full-screen VHS/CRT shader that gets *wrong* as dread rises.

---

## Run it (Mac — priority platform)

1. Open **Godot 4.7** (`~/Downloads/Godot.app`).
2. **Import** → pick `SafeMode/project.godot` → **Edit**.
3. Press **F5** (Run Project). Pick **SOLO** to play alone.

Or from a terminal, straight into a solo run:

```
~/Downloads/Godot.app/Contents/MacOS/Godot --path ~/SafeMode -- --solo
```

### Controls

| Action | Key |
|---|---|
| Move | `WASD` / arrows |
| Sprint | `Shift` |
| Jump | `Space` |
| Look | Mouse |
| **Laser** (hold on a task console, or on the malware once armed) | **Left mouse** |
| Flashlight | `F` |
| Push-to-talk (co-op) | `V` |
| Free the mouse | `Esc` (click to grab it back) |
| Fullscreen toggle | `F11` |

**Goal:** the **malware — a red sphere — boots into a random room the instant you drop
in**, and a **six-minute** countdown starts. Your laser can't scratch it yet.

1. **Recover all seven components** by completing a task in each component room — the
   **motherboard, CPU, GPU, two RAM modules, SSD, and power supply**. Hold your laser
   on the room's console until the bar fills. The HUD tracks `COMPONENTS x / 7`.
2. All seven **arms the laser** (it turns from green to hot red).
3. **Delete the malware.** Hold the armed laser on the red sphere until its health bar
   empties.

Meanwhile the malware sheds **parasites** — red, jittering things that chase you. An
armed laser pops them; unarmed, you can only run.

**Four endings:**

- **MALWARE DELETION** *(win)* — you burned down the red sphere before the timer.
- **SUCCESSFULLY FAILED** *(win)* — the timer ran out, the drive began **deleting
  itself** room by room in a blackout, and you **escaped to the USB in the motherboard
  ports** before your sector was erased.
- **PARASITE** *(lose)* — a parasite drained you to zero.
- **FILE DELETION** *(lose)* — you were standing in a room when it was deleted.

When the clock hits zero the lights die and rooms start vanishing from the map (farthest
from the motherboard first), so escaping means running *toward* the USB while the floor
disappears behind you.

---

## Co-op (host / join)

1. One player picks **HOST** (listens on UDP **24545**, up to 5).
2. Others pick **JOIN** and enter the host's IP (blank = `127.0.0.1` for two
   instances on the same machine).
3. **Proximity voice:** hold **`V`** to transmit. Teammates are heard in 3D — closer
   is louder — because each remote player is a positional audio source.

Testing two instances locally: run the project twice (Godot lets you launch multiple
instances; or use `--path` from two terminals). Host in one, join `127.0.0.1` in the
other.

---

## What works today vs. what's next

This is a **playable vertical slice** with everything scaffolded. Solo is the fully
wired path; co-op connects, replicates movement + the monster + voice, and shares the
world.

**Working now**
- First-person controller, flashlight, laser tool, `Esc`/click mouse handling,
  `F11` fullscreen.
- Code-built PC interior: an **11-room looping map** on a wide grid, wired from an
  adjacency list, with **every room decorated as its component** — the motherboard is a
  PCB with capacitors, a socket, RAM rails and the USB port header; the CPU room is a
  finned heatsink over a pin grid; the GPU has fans and VRAM; RAM rooms are stick
  monoliths; the PSU has capacitors and cable runs; plus a spinning system fan, cache
  shelves, and a NIC jack.
- **Task-to-arm objective:** complete a hold-the-laser task in each of the 7 component
  rooms → arms the laser → delete the malware. Three-step goal + `6:00` countdown +
  malware health bar on the HUD.
- **The malware** is a red sphere that **spawns in a random room the instant the game
  starts**, drifts and flees from an armed player, and can only be hurt once the laser
  is armed. It sheds **parasites** — red, jittering chasers that an armed laser pops.
- **Six-minute timer → self-deletion:** if the malware is still alive at zero, the
  lights die and rooms are erased one by one (farthest from the motherboard first);
  reach the **USB in the motherboard** to escape.
- **Four endings** (`ENDINGS` in `Main.gd`): Malware Deletion, Successfully Failed,
  Parasite, File Deletion — chosen by *how* the run ended, with death carrying a cause.
- **Atmosphere director** (`src/horror/Horror.gd`): corruption-driven VHS shader,
  tiered liminal "research" lines, and scripted **dread beats** — blackouts, a false
  teammate connecting/disconnecting, the machine calling you by your login name, static
  surges. Edit the lines in `LINES_CALM/UNEASY/WRONG`.
- **Procedural audio** (`src/audio/Sound.gd`): fully synthesized, zero audio files — a
  drone that swells with dread, a heartbeat that quickens as the malware nears, and
  stingers for purge/hit/unlock/whisper/growl.
- Networking: host/join over ENet, replicated player + malware transforms, and
  **host-authoritative game state** — clients only *request* component pickups and
  beam-hits over RPC; the host applies them and mirrors collected parts, armed state,
  malware health, and win/lose to everyone.
- Proximity voice chat (prototype): push-to-talk mic → peers → 3D playback.

**Next (honest TODOs, marked in code)**
- **Downed/revive** co-op loop (right now a downed player spectates; the run ends when
  everyone is down, or when the infection dies).
- **Voice**: swap raw PCM for Opus + a jitter buffer; currently LAN-grade.
- More monster variety and scripted dread beats.

---

## Cross-platform export

Mac is the priority and runs natively via Metal. For the others, in Godot:
**Project → Export** (install export templates when prompted).

- **Windows:** add a *Windows Desktop* preset → Export. Uses Vulkan/D3D12.
- **ChromeOS / browser:** add a *Web* preset → Export. The project auto-switches to
  the `gl_compatibility` (OpenGL) renderer on web (`project.godot`). Note: browser
  mic/voice and networking are more restricted than native — expect to host natively
  and have web clients join, and treat web voice as best-effort.

---

## Project layout

```
project.godot            renderer, autoloads, window
scenes/Main.tscn         root → src/Main.gd (menu + session orchestration)
src/net/Net.gd           autoload: networking + input registration
src/audio/Sound.gd       autoload: synthesized drone / heartbeat / stingers
src/horror/Horror.gd     autoload: dread director + liminal lines + dread beats
src/voice/VoiceChat.gd   autoload: proximity voice (prototype)
src/world/WorldBuilder.gd builds the interior in code
src/world/CorruptionNode.gd  the purge objectives
src/world/FlickerLight.gd    unreliable lights
src/player/Player.*      first-person controller (built in code)
src/enemies/Malware.*    the physical malware AI
src/ui/HUD.gd            crosshair, vitals, objective, flash messages
src/fx/vhs.gdshader      analog-horror post-process
```
