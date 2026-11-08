#[derive(Debug, thiserror::Error)]
pub enum DatabaseError {
    #[error("{0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("La base de datos es de una versión más nueva ({0}) que esta aplicación.")]
    TooNew(i64),
    #[error("El acceso a la base de datos quedó bloqueado por un fallo anterior.")]
    Poisoned,
}

pub type Result<T, E = DatabaseError> = std::result::Result<T, E>;

impl<T> From<std::sync::PoisonError<T>> for DatabaseError {
    fn from(_: std::sync::PoisonError<T>) -> Self {
        DatabaseError::Poisoned
    }
}

impl From<rusqlite::types::FromSqlError> for DatabaseError {
    fn from(error: rusqlite::types::FromSqlError) -> Self {
        DatabaseError::Sqlite(rusqlite::Error::FromSqlConversionFailure(
            0,
            rusqlite::types::Type::Null,
            Box::new(error),
        ))
    }
}
