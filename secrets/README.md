# Local secrets

Nothing in this directory is committed, and nothing in it should ever be.

`hevy-key.txt` holds a Hevy API key. `scripts/build.sh` injects it into the
build as the default value of the `hevyApiKey` setting, so a sideloaded watch
arrives already able to talk to Hevy without typing 36 characters on a phone.

**A build made this way is personal.** The key is read *and* write over the
whole of that person's training history, it cannot be scoped, and anyone who
installs the resulting `.prg` has it. Never publish a build made with a key in
place: `make package` refuses to, and `scripts/doctor.sh` checks that no key has
found its way into a tracked file.
