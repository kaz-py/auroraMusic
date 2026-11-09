//! Acceso mínimo a `libvosk` cargada en tiempo de ejecución.
//!
//! No se enlaza en la compilación a propósito: si la biblioteca faltara, el
//! motor de Rust entero (y con él la app) no podría cargarse. Así, sin ella
//! solo falla esta función, con un mensaje claro.

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::path::Path;
use std::sync::Arc;

use libloading::Library;

use crate::command::Word;
use crate::VoiceError;

type ModelNew = unsafe extern "C" fn(*const c_char) -> *mut c_void;
type ModelFree = unsafe extern "C" fn(*mut c_void);
type FindWord = unsafe extern "C" fn(*mut c_void, *const c_char) -> c_int;
type RecNewGrm = unsafe extern "C" fn(*mut c_void, f32, *const c_char) -> *mut c_void;
type RecNew = unsafe extern "C" fn(*mut c_void, f32) -> *mut c_void;
type RecFree = unsafe extern "C" fn(*mut c_void);
type SetWords = unsafe extern "C" fn(*mut c_void, c_int);
type Accept = unsafe extern "C" fn(*mut c_void, *const i16, c_int) -> c_int;
type Text = unsafe extern "C" fn(*mut c_void) -> *const c_char;
type SetLog = unsafe extern "C" fn(c_int);

struct Api {
    model_new: ModelNew,
    model_free: ModelFree,
    find_word: FindWord,
    rec_new_grm: RecNewGrm,
    rec_new: RecNew,
    rec_free: RecFree,
    set_words: SetWords,
    accept: Accept,
    result: Text,
    final_result: Text,
    // Última: descarga la biblioteca cuando ya nada la usa.
    _lib: Library,
}

// SAFETY: los punteros de función son de una biblioteca que no se descarga
// mientras viva el `Api`; las funciones de Vosk no dependen del hilo que las llama.
unsafe impl Send for Api {}
unsafe impl Sync for Api {}

pub struct Vosk(Arc<Api>);

fn open(path: &Path) -> Result<Library, libloading::Error> {
    #[cfg(windows)]
    {
        // Las DLL de las que depende (libstdc++, libgcc…) están junto a ella.
        const LOAD_WITH_ALTERED_SEARCH_PATH: u32 = 0x8;
        // SAFETY: cargar una biblioteca ejecuta su código de inicio; es la que Aurora instala.
        unsafe {
            libloading::os::windows::Library::load_with_flags(path, LOAD_WITH_ALTERED_SEARCH_PATH)
                .map(Library::from)
        }
    }
    #[cfg(not(windows))]
    {
        // SAFETY: igual que arriba.
        unsafe { Library::new(path) }
    }
}

impl Vosk {
    pub fn load(path: &Path) -> Result<Self, VoiceError> {
        let missing = |what: String| VoiceError::Library(what);
        let lib = open(path).map_err(|e| {
            missing(format!(
                "No se pudo cargar la biblioteca de voz ({}): {e}",
                path.display()
            ))
        })?;
        macro_rules! symbol {
            ($name:literal, $ty:ty) => {
                // SAFETY: la firma coincide con `vosk_api.h` (versión 0.3.x).
                *unsafe { lib.get::<$ty>(concat!($name, "\0").as_bytes()) }.map_err(|e| {
                    missing(format!("A la biblioteca de voz le falta {}: {e}", $name))
                })?
            };
        }
        let api = Api {
            model_new: symbol!("vosk_model_new", ModelNew),
            model_free: symbol!("vosk_model_free", ModelFree),
            find_word: symbol!("vosk_model_find_word", FindWord),
            rec_new_grm: symbol!("vosk_recognizer_new_grm", RecNewGrm),
            rec_new: symbol!("vosk_recognizer_new", RecNew),
            rec_free: symbol!("vosk_recognizer_free", RecFree),
            set_words: symbol!("vosk_recognizer_set_words", SetWords),
            accept: symbol!("vosk_recognizer_accept_waveform_s", Accept),
            result: symbol!("vosk_recognizer_result", Text),
            final_result: symbol!("vosk_recognizer_final_result", Text),
            _lib: {
                let log: SetLog = symbol!("vosk_set_log_level", SetLog);
                // SAFETY: -1 silencia los registros de Kaldi.
                unsafe { log(-1) };
                lib
            },
        };
        Ok(Self(Arc::new(api)))
    }

    pub fn model(&self, dir: &Path) -> Result<Model, VoiceError> {
        let path = native_path(dir)?;
        // SAFETY: `path` es una cadena C válida durante la llamada.
        let ptr = unsafe { (self.0.model_new)(path.as_ptr()) };
        if ptr.is_null() {
            return Err(VoiceError::Model(format!(
                "No se pudo cargar el modelo de voz en {}. Vuelve a descargarlo desde Ajustes.",
                dir.display()
            )));
        }
        Ok(Model {
            api: self.0.clone(),
            ptr,
        })
    }
}

pub struct Model {
    api: Arc<Api>,
    ptr: *mut c_void,
}

// SAFETY: el modelo es de solo lectura tras crearse.
unsafe impl Send for Model {}
unsafe impl Sync for Model {}

impl Model {
    /// ¿Conoce el modelo esta palabra? (Vosk ignora en silencio las que no.)
    pub fn knows(&self, word: &str) -> bool {
        let Ok(c) = CString::new(word) else {
            return false;
        };
        // SAFETY: puntero de modelo vivo y cadena C válida.
        unsafe { (self.api.find_word)(self.ptr, c.as_ptr()) >= 0 }
    }

    /// Reconocedor a `rate` Hz, restringido a [grammar] (arreglo JSON) si se da.
    pub fn recognizer(
        self: &Arc<Self>,
        rate: f32,
        grammar: Option<&str>,
    ) -> Result<Recognizer, VoiceError> {
        let ptr = match grammar {
            Some(g) => {
                let c =
                    CString::new(g).map_err(|_| VoiceError::Model("Gramática inválida.".into()))?;
                // SAFETY: modelo vivo; cadena C válida.
                unsafe { (self.api.rec_new_grm)(self.ptr, rate, c.as_ptr()) }
            }
            // SAFETY: modelo vivo.
            None => unsafe { (self.api.rec_new)(self.ptr, rate) },
        };
        if ptr.is_null() {
            return Err(VoiceError::Model("No se pudo crear el reconocedor.".into()));
        }
        // SAFETY: recién creado y no nulo.
        unsafe { (self.api.set_words)(ptr, 1) };
        Ok(Recognizer {
            model: self.clone(),
            ptr,
        })
    }
}

impl Drop for Model {
    fn drop(&mut self) {
        // SAFETY: único dueño; los reconocedores guardan un `Arc` y mueren antes.
        unsafe { (self.api.model_free)(self.ptr) };
    }
}

pub struct Recognizer {
    model: Arc<Model>,
    ptr: *mut c_void,
}

// SAFETY: se usa desde un solo hilo a la vez (lo mueve el hilo de escucha).
unsafe impl Send for Recognizer {}

impl Recognizer {
    /// Entrega audio mono de 16 bits. `true` si terminó una frase: hay
    /// resultado en [`Recognizer::result`].
    pub fn accept(&mut self, pcm: &[i16]) -> bool {
        if pcm.is_empty() {
            return false;
        }
        // SAFETY: `pcm` es válido durante la llamada; la longitud es en muestras.
        unsafe { (self.model.api.accept)(self.ptr, pcm.as_ptr(), pcm.len() as c_int) == 1 }
    }

    pub fn result(&mut self) -> Vec<Word> {
        // SAFETY: reconocedor vivo.
        parse(unsafe { (self.model.api.result)(self.ptr) })
    }

    /// Lo que quede por reconocer (al terminar el audio).
    pub fn final_result(&mut self) -> Vec<Word> {
        // SAFETY: reconocedor vivo.
        parse(unsafe { (self.model.api.final_result)(self.ptr) })
    }
}

impl Drop for Recognizer {
    fn drop(&mut self) {
        // SAFETY: único dueño; el modelo sigue vivo por el `Arc`.
        unsafe { (self.model.api.rec_free)(self.ptr) };
    }
}

fn parse(ptr: *const c_char) -> Vec<Word> {
    if ptr.is_null() {
        return Vec::new();
    }
    // SAFETY: Vosk devuelve una cadena C válida hasta la siguiente llamada.
    let text = unsafe { CStr::from_ptr(ptr) }.to_string_lossy();
    parse_json(&text)
}

/// `{"result":[{"conf":0.9,"word":"aurora",…}],"text":"aurora pausa"}`.
pub fn parse_json(json: &str) -> Vec<Word> {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    value["result"]
        .as_array()
        .map(|words| {
            words
                .iter()
                .filter_map(|w| {
                    Some(Word {
                        text: w["word"].as_str()?.to_string(),
                        confidence: w["conf"].as_f64()? as f32,
                        start: w["start"].as_f64().unwrap_or(0.0) as f32,
                        end: w["end"].as_f64().unwrap_or(0.0) as f32,
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn result_json_becomes_words_with_confidence() {
        let words = parse_json(
            r#"{"result":[{"conf":1.0,"end":1.2,"start":0.5,"word":"aurora"},
                          {"conf":0.75,"end":1.9,"start":1.3,"word":"pausa"}],
                "text":"aurora pausa"}"#,
        );
        assert_eq!(words.len(), 2);
        assert_eq!(words[0].text, "aurora");
        assert_eq!(words[1].confidence, 0.75);
        assert!(parse_json(r#"{"text":""}"#).is_empty());
        assert!(parse_json("no es json").is_empty());
    }
}

/// Ruta como la espera Vosk. Kaldi abre los archivos con `fopen`, que en
/// Windows lee la página de códigos ANSI (no UTF-8): «C:\Users\José» solo
/// funciona convertida a ANSI.
#[cfg(windows)]
fn native_path(dir: &Path) -> Result<CString, VoiceError> {
    use std::os::windows::ffi::OsStrExt;
    extern "system" {
        fn WideCharToMultiByte(
            code_page: u32,
            flags: u32,
            wide: *const u16,
            wide_len: c_int,
            narrow: *mut u8,
            narrow_len: c_int,
            default_char: *const u8,
            used_default: *mut c_int,
        ) -> c_int;
    }
    const CP_ACP: u32 = 0;
    let wide: Vec<u16> = dir.as_os_str().encode_wide().collect();
    let bad = || {
        VoiceError::Model(format!(
            "La ruta del modelo de voz ({}) tiene caracteres que el reconocedor no admite. \
             Usa una cuenta de Windows cuyo nombre no los tenga.",
            dir.display()
        ))
    };
    if wide.is_empty() || wide.len() > c_int::MAX as usize {
        return Err(bad());
    }
    let mut used_default: c_int = 0;
    // SAFETY: búferes válidos con sus longitudes; primero se mide, luego se convierte.
    let size = unsafe {
        WideCharToMultiByte(
            CP_ACP,
            0,
            wide.as_ptr(),
            wide.len() as c_int,
            std::ptr::null_mut(),
            0,
            std::ptr::null(),
            &mut used_default,
        )
    };
    if size <= 0 {
        return Err(bad());
    }
    let mut narrow = vec![0u8; size as usize];
    // SAFETY: `narrow` tiene `size` bytes.
    let written = unsafe {
        WideCharToMultiByte(
            CP_ACP,
            0,
            wide.as_ptr(),
            wide.len() as c_int,
            narrow.as_mut_ptr(),
            size,
            std::ptr::null(),
            &mut used_default,
        )
    };
    if written <= 0 || used_default != 0 {
        return Err(bad());
    }
    CString::new(narrow).map_err(|_| bad())
}

#[cfg(not(windows))]
fn native_path(dir: &Path) -> Result<CString, VoiceError> {
    use std::os::unix::ffi::OsStrExt;
    CString::new(dir.as_os_str().as_bytes())
        .map_err(|_| VoiceError::Model("La ruta del modelo de voz no es válida.".into()))
}
