//! Decodificador Opus: libopus transpilada a Rust (`unsafe-libopus`), sin C ni
//! CMake. Es ~100× más rápida que el decodificador de Rust puro que se usaba
//! antes (que iba a ~2,3× tiempo real en un Ryzen 5 7600: en un equipo más
//! lento el audio de YouTube —Opus— salía entrecortado).

use unsafe_libopus::{
    opus_decode_float, opus_decoder_create, opus_decoder_ctl, opus_decoder_destroy,
    OpusDecoder as RawDecoder, OPUS_RESET_STATE,
};

/// Mayor trama que puede devolver un paquete: 120 ms a 48 kHz.
pub(crate) const MAX_FRAME: usize = 5760;

pub(crate) struct OpusDec {
    raw: *mut RawDecoder,
    channels: usize,
}

// El estado de libopus no se comparte: lo usa un solo hilo a la vez.
unsafe impl Send for OpusDec {}

impl OpusDec {
    pub(crate) fn new(channels: usize) -> Result<Self, i32> {
        let mut error = 0;
        // SAFETY: `error` es un entero válido durante la llamada.
        let raw = unsafe { opus_decoder_create(48_000, channels as i32, &mut error) };
        if raw.is_null() || error != 0 {
            return Err(error);
        }
        Ok(Self { raw, channels })
    }

    /// Decodifica un paquete a `pcm` (intercalado); devuelve las tramas por canal.
    pub(crate) fn decode_float(&mut self, data: &[u8], pcm: &mut [f32]) -> Result<usize, i32> {
        let room = (pcm.len() / self.channels).min(MAX_FRAME);
        // SAFETY: `raw` es un decodificador vivo; `data` y `pcm` son rangos
        // válidos y `room` tramas por canal caben en `pcm`.
        let frames = unsafe {
            opus_decode_float(
                self.raw,
                data.as_ptr(),
                data.len() as i32,
                pcm.as_mut_ptr(),
                room as i32,
                0,
            )
        };
        usize::try_from(frames).map_err(|_| frames)
    }

    pub(crate) fn reset(&mut self) {
        // SAFETY: `raw` es un decodificador vivo.
        unsafe { opus_decoder_ctl!(self.raw, OPUS_RESET_STATE) };
    }
}

impl Drop for OpusDec {
    fn drop(&mut self) {
        // SAFETY: `raw` salió de `opus_decoder_create` y no se usa después.
        unsafe { opus_decoder_destroy(self.raw) };
    }
}
