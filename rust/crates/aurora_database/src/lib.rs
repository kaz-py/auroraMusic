//! Base de datos SQLite de la biblioteca de Aurora.
//!
//! El JSON de pistas se guarda y devuelve tal cual: este crate nunca lo
//! interpreta. Todo el SQL es el que escribía la versión Dart con drift.

mod error;
mod library;
mod schema;

pub use error::{DatabaseError, Result};
pub use library::*;
pub use schema::SCHEMA_VERSION;
