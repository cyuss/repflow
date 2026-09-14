import Toybox.Lang;

//! A Hevy API key compiled into the build, or nothing.
//!
//! **This file is committed with an empty key and must stay that way.**
//! `scripts/build.sh` rewrites it for a personal build from
//! `secrets/hevy-key.txt`, and puts it back afterwards; `make doctor` checks the
//! committed copy, and `make package` refuses to build a Store bundle while a
//! key is in play.
//!
//! Why a constant rather than the setting's default value, which is where this
//! started: Connect IQ applies a property's default **only on a first install**.
//! An update keeps whatever the property already held, so a watch that had
//! RepFlow before the key existed kept the empty string and went on reporting
//! "No API key" with the key sitting unread inside the very build it came from.
//!
//! A constant has no such history. It is read last, after Storage and after the
//! phone's setting, so anything the athlete enters still wins over it.
module HevyKey {

    //! Empty in every committed build. See the module comment.
    const COMPILED = "";

    public function compiled() as String {
        return COMPILED;
    }
}
