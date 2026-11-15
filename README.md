# Humans vs Clickers

A multiplayer horror game mode for [Teardown](https://teardowngame.com). Blind clickers hunt the humans by sound:
the humans get a head start to hide, then must survive until the time runs out.

**Steam Workshop:** https://steamcommunity.com/sharedfiles/filedetails/?id=3822711185

## How to play

Host a multiplayer session on any map, pick **Humans vs Clickers** as the game mode, choose teams in the lobby and
press Start. Players who don't pick a team join the humans; if nobody picks the clickers, a random player becomes one.

### Humans

- Start with a gun, a sledgehammer, 5 planks and 2 goo grenades. Hide, barricade, fight back. About half the humans also
  get a noisemaker (a coin flip each round; always at least one of you, never everyone).
- The goo grenade bursts where it hits into a wall of grey foam across the way you threw it: block a doorway with it.
  Clickers tear through it, bullets and sledges break it, and broken bits vanish after a few seconds. A player or clicker
  it hits is stuck in a foam cocoon for 5 seconds, unless they break out (4 sledge swings, or 3 strikes for a clicker).
- The noisemaker is a decoy: throw it, and where it lands it fires gunshots for 7 seconds. To a clicker it looks like you
  shooting from there.
- Every sound you make can give you away: footsteps (crouch-walk to move silently), gunshots, tools, vehicles, talking.
- A clicker's strike takes half your health; at zero you are **downed** and crawl. A teammate holding **E** next to
  you for 5 seconds helps you up. If nobody does, you bleed out.
- You slowly heal back up to 40 % health, starting 6 seconds after you last took damage.
- Shoot or hit a clicker enough and it is stunned for a few seconds.

### Clickers

- You are blind: you see only what is right in front of you, and every sound shows you where it came from.
- **F**: echolocation - a loud click that reveals the humans around you.
- **LMB**: strike / tear through walls (steel too). **RMB**: grab and carry things, drag doors open; **LMB** throws.
- **Shift**: run (uses stamina). Stand still for 7 seconds to sense the humans' heartbeats.

**L** shows the scoreboard (downs, kills, revives, damage).

### Host settings

Round time, head start, time of day, and whether Global chat stays on during the round.

## Works with these mods (optional)

- [Clamber: Climbing, Ladders & Mantling](https://steamcommunity.com/sharedfiles/filedetails/?id=3835599376): ladders
  and climbable walls for everyone. Clickers climb too, with their own climbing animation, and reach higher.
- [McPuppet Inventory System](https://steamcommunity.com/sharedfiles/filedetails/?id=3840357667): gold and an
  inventory for the humans. Everyone earns gold each round (+120 a win, -80 a loss, never below 0), a clicker +10 for
  every human it catches, and nobody loses gold or items when they die. Clickers spend their gold in their own upgrade
  shop (I): more stamina, more attack power (+5 a level, up to +25: thicker arms), a double jump with wings, a laser
  beam from the maw (hold LMB 2 s; all your stamina, 45 s to recharge) and faster echolocation. The humans' round
  tools are items on its hotbar, handed out each round and taken back at its end.
- [McPuppet Basic Clothing Pack Vol 1](https://steamcommunity.com/sharedfiles/filedetails/?id=3840291332): with the
  Inventory, armour for the humans; it reduces the clickers' strikes and laser.
- [McPuppet Basic Melee Weapons Pack Vol 1](https://steamcommunity.com/sharedfiles/filedetails/?id=3840291496),
  [McPuppet Basic Guns Pack Vol 1](https://steamcommunity.com/sharedfiles/filedetails/?id=3840508226) and
  [McPuppet Basic Tools Pack Vol 1](https://steamcommunity.com/sharedfiles/filedetails/?id=3840508314): with the
  Inventory, more weapons and tools for the humans; the melee weapons and guns hurt the clickers too.

Without them the game plays as described above.

## Proximity Comms

With the [Proximity Comms](https://steamcommunity.com/sharedfiles/filedetails/?id=3812301496) mod enabled, the
humans talk by proximity (and the clickers hear them), pings go only to your own team, and the caught talk on the
dead's channel.

## Install from this repository

Copy this folder into `Documents/Teardown/mods/` and enable it from the Mod Manager's local files. Multiplayer
sessions only accept Workshop mods, so to play online use the Workshop item above.

## Credits

- Made by AgeOfAlgorithms.
- [mplib](https://github.com/tuxedolabsorg/mplib) by Tuxedo Labs, MIT (`mplib/LICENSE`).
- Pain screams and the clickers' clicking were generated with
  [MOSS-SoundEffect v2.0](https://github.com/OpenMOSS/MOSS-TTS) and [Dia](https://github.com/nari-labs/dia)
  (both Apache-2.0); other sounds are synthesized or Teardown's own.

## License

MIT - see `LICENSE`.
