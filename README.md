# Humans vs Clickers

A multiplayer horror game mode for [Teardown](https://teardowngame.com). Blind clickers hunt the humans by sound:
the humans get a head start to hide, then must survive until the time runs out.

**Steam Workshop:** https://steamcommunity.com/sharedfiles/filedetails/?id=3822711185

## How to play

Host a multiplayer session on any map, pick **Humans vs Clickers** as the game mode, choose teams in the lobby and
press Start. Players who don't pick a team join the humans; if nobody picks the clickers, a random player becomes one.

### Humans

- Start with a gun, a sledgehammer and 5 planks. Hide, barricade, fight back. About half the humans also get a noisemaker
  (a coin flip each round; always at least one of you, never everyone).
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
