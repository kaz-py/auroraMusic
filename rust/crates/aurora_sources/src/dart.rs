//! Semántica de Dart sobre JSON dinámico.
//!
//! Los analizadores de `innertube_source.dart` navegan `dynamic` con `?[...]` y
//! conversiones `as String?`. Dart lanza un error si el tipo no es el esperado;
//! aquí se devuelve `Err` en los mismos puntos, para que una respuesta mal
//! formada siga contando como fallo de la fuente y no como «vacío».

use serde_json::{Map, Value};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError(pub String);

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ParseError {}

pub type R<T, E = ParseError> = Result<T, E>;

fn err<T>(what: &str, got: &Value) -> R<T> {
    Err(ParseError(format!(
        "{what}: se esperaba otro tipo, llegó {}",
        kind(got)
    )))
}

fn kind(v: &Value) -> &'static str {
    match v {
        Value::Null => "null",
        Value::Bool(_) => "bool",
        Value::Number(_) => "número",
        Value::String(_) => "texto",
        Value::Array(_) => "lista",
        Value::Object(_) => "mapa",
    }
}

/// `null` de JSON y ausencia son lo mismo para `?.` y `??`.
pub fn nn(v: Option<&Value>) -> Option<&Value> {
    v.filter(|v| !v.is_null())
}

/// `v?[key]` con `v` dinámico: `null` corta; un mapa se indexa; cualquier otro
/// tipo lanza (indexar un `String`/`List` con un `String` es un error en Dart).
pub fn idx<'a>(v: Option<&'a Value>, key: &str) -> R<Option<&'a Value>> {
    match nn(v) {
        None => Ok(None),
        Some(Value::Object(m)) => Ok(nn(m.get(key))),
        Some(other) => err(&format!("[\"{key}\"]"), other),
    }
}

/// `idx` encadenado: `v?[a]?[b]?[c]`.
pub fn path<'a>(v: Option<&'a Value>, keys: &[&str]) -> R<Option<&'a Value>> {
    let mut cur = v;
    for key in keys {
        cur = idx(cur, key)?;
    }
    Ok(cur)
}

/// `x as String?`
pub fn as_str(v: Option<&Value>) -> R<Option<&str>> {
    match nn(v) {
        None => Ok(None),
        Some(Value::String(s)) => Ok(Some(s)),
        Some(other) => err("as String?", other),
    }
}

/// `x as Map?`
pub fn as_map(v: Option<&Value>) -> R<Option<&Map<String, Value>>> {
    match nn(v) {
        None => Ok(None),
        Some(Value::Object(m)) => Ok(Some(m)),
        Some(other) => err("as Map?", other),
    }
}

/// `x as List?`
pub fn as_list(v: Option<&Value>) -> R<Option<&Vec<Value>>> {
    match nn(v) {
        None => Ok(None),
        Some(Value::Array(a)) => Ok(Some(a)),
        Some(other) => err("as List?", other),
    }
}

/// `x as num?` (como `f64`; solo se compara).
pub fn as_num(v: Option<&Value>) -> R<Option<f64>> {
    match nn(v) {
        None => Ok(None),
        Some(Value::Number(n)) => Ok(n.as_f64()),
        Some(other) => err("as num?", other),
    }
}

/// `x as Map` (no nulo).
pub fn must_map(v: &Value) -> R<&Map<String, Value>> {
    match v {
        Value::Object(m) => Ok(m),
        other => err("as Map", other),
    }
}

/// `Value::to_string()` de Dart para un elemento dinámico (`join()` de textos).
pub fn dart_string(v: &Value) -> String {
    match v {
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => match n.as_i64() {
            Some(i) => i.to_string(),
            None => format!("{:?}", n.as_f64().unwrap_or(f64::NAN)),
        },
        Value::String(s) => s.clone(),
        Value::Array(a) => format!(
            "[{}]",
            a.iter().map(dart_string).collect::<Vec<_>>().join(", ")
        ),
        Value::Object(m) => format!(
            "{{{}}}",
            m.iter()
                .map(|(k, v)| format!("{k}: {}", dart_string(v)))
                .collect::<Vec<_>>()
                .join(", ")
        ),
    }
}

fn is_dart_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n'
            | '\u{0B}'
            | '\u{0C}'
            | '\r'
            | ' '
            | '\u{85}'
            | '\u{A0}'
            | '\u{1680}'
            | '\u{2000}'
            ..='\u{200A}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202F}'
                | '\u{205F}'
                | '\u{3000}'
                | '\u{FEFF}'
    )
}

/// `String.trim` de Dart.
pub fn trim(s: &str) -> &str {
    s.trim_matches(is_dart_space)
}

/// `String.toLowerCase` de Dart (asignación simple; ver `aurora_ai_dj::text`).
pub fn lower(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if c == '\u{130}' {
            out.push('i');
        } else {
            out.extend(c.to_lowercase());
        }
    }
    out
}

/// Lo que `innertube_source.dart` pregunta de `Uri.tryParse(url)`:
/// `None` si Dart devolvería `null`; si no, `(scheme, userinfo no vacío)`.
///
/// Aproximación RFC 3986 de la parte que importa (esquema, autoridad, puerto y
/// caracteres del host); los casos límite se fijan con el corpus de oro.
pub fn uri_scheme_userinfo(url: &str) -> Option<(String, bool)> {
    let mut scheme = String::new();
    let mut rest = url;
    if let Some(colon) = url.find(':') {
        let head = &url[..colon];
        let mut chars = head.chars();
        let valid = chars.next().is_some_and(|c| c.is_ascii_alphabetic())
            && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'));
        if valid {
            scheme = head.to_ascii_lowercase();
            rest = &url[colon + 1..];
        }
    }
    let mut userinfo = false;
    if let Some(after) = rest.strip_prefix("//") {
        let end = after.find(['/', '?', '#']).unwrap_or(after.len());
        let authority = &after[..end];
        let (info, hostport) = match authority.find('@') {
            Some(at) => (&authority[..at], &authority[at + 1..]),
            None => ("", authority),
        };
        if hostport.contains('@') {
            return None;
        }
        userinfo = !info.is_empty();
        let _host = if let Some(stripped) = hostport.strip_prefix('[') {
            // IPv6 entre corchetes: el puerto va tras `]`.
            let close = stripped.find(']')?;
            if stripped[..close].parse::<std::net::Ipv6Addr>().is_err() {
                return None;
            }
            let tail = &stripped[close + 1..];
            if !(tail.is_empty()
                || (tail.starts_with(':') && tail[1..].bytes().all(|b| b.is_ascii_digit())))
            {
                return None;
            }
            &stripped[..close]
        } else {
            if hostport.contains(['[', ']']) || hostport.matches(':').count() > 1 {
                return None;
            }
            match hostport.rfind(':') {
                Some(colon) => {
                    if !hostport[colon + 1..].bytes().all(|b| b.is_ascii_digit()) {
                        return None;
                    }
                    &hostport[..colon]
                }
                None => hostport,
            }
        };
    }
    Some((scheme, userinfo))
}
