# Developer signing key

Every Connect IQ binary must be signed with a developer key. RepFlow's key is
an RSA 4096-bit private key in unencrypted PKCS#8 DER form, which is what
`monkeyc -y` expects.

## Where it lives

```
~/.garmin/repflow/developer_key.der    # used by monkeyc
~/.garmin/repflow/developer_key.pem    # the same key in PEM, for backup
```

**Outside the repository, always.** Override the location with the
`REPFLOW_DEVELOPER_KEY` environment variable if you keep keys somewhere else:

```sh
export REPFLOW_DEVELOPER_KEY="$HOME/keys/garmin/repflow.der"
```

## How builds find it

`scripts/lib.sh` resolves `DEVELOPER_KEY` from `$REPFLOW_DEVELOPER_KEY`, falling
back to the default path. Every script that compiles (`build.sh`, `test.sh`,
`package.sh`) passes it to `monkeyc` with `-y`. Nothing hard-codes a path.

## How to create it

```sh
make key          # or: scripts/make-developer-key.sh
```

The script **never overwrites an existing key**. It runs, in effect:

```sh
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in developer_key.pem -out developer_key.der -nocrypt
```

On Windows without openssl, `bootstrap-windows.ps1` falls back to
.NET's `RSA.ExportPkcs8PrivateKey()`, which produces the identical format.

## How to back it up

Do this now, not later.

1. Copy `developer_key.pem` into a password manager as a secure note or
   attachment, or into an encrypted archive you actually keep
   (`age`, `gpg`, an encrypted disk image).
2. Store it somewhere that survives losing this machine.
3. Never put it in the repository, a shared drive, a chat message, an issue
   tracker, or CI environment variables you do not control.

To restore on a new machine, put the `.pem` back and regenerate the DER:

```sh
mkdir -p ~/.garmin/repflow && chmod 700 ~/.garmin/repflow
cp restored.pem ~/.garmin/repflow/developer_key.pem
openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in  ~/.garmin/repflow/developer_key.pem \
        -out ~/.garmin/repflow/developer_key.der -nocrypt
chmod 600 ~/.garmin/repflow/*
```

## Why losing it is serious

The Connect IQ Store ties a published app to the key that signed it. If you
lose the key:

- you **cannot publish an update** to the existing RepFlow listing;
- your only option is to publish a **new** app, with a new listing, new UUID
  and zero installs — existing users are orphaned and never see the update.

There is no recovery process and Garmin cannot re-issue it.

## The application UUID

`manifest.xml` carries the application id:

```
289C529B638645F0B9A7334DF736972B
```

This is a second identity that must be preserved. Once RepFlow is published:

- **never** regenerate the UUID;
- **never** let a tool regenerate it for you (VS Code's "Monkey C: New Project"
  creates a fresh one — do not run it against this repo);
- treat a changed UUID in a diff as a release-blocking bug.

Changing it creates a different application as far as the Store is concerned,
with the same consequences as losing the key.

## Protection in this repository

`.gitignore` excludes `*.der`, `*.pem`, `*.key`, `*.p12`, `*.pfx`,
`developer_key*`, `keys/` and `.keys/`. `scripts/doctor.sh` additionally fails
if it finds the key tracked by git.

Verify at any time:

```sh
git ls-files | grep -Ei '\.(der|pem|key|p12|pfx)$'   # must print nothing
```
