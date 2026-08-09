//! Raw bindings generated from `strok/c_api.h` at build time.
//!
//! This crate intentionally exposes only unsafe C ABI declarations. Callers must
//! preserve the C API's handle ownership, borrowing, thread-safety, and lifetime
//! rules; no safe Rust ownership layer is provided here.

#![allow(
    clippy::all,
    non_camel_case_types,
    non_snake_case,
    non_upper_case_globals
)]

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
