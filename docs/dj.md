# DJ personalizado

El DJ es un algoritmo propio, local y determinista: no usa servicios de IA,
claves de API ni la radio/«up next» de YouTube. YouTube es solo la fuente de
audio; las búsquedas sirven únicamente para obtener canciones reproducibles.

- `lib/dj/ai_dj.dart`: vectores de canciones, perfil de gustos, consultas de
  descubrimiento y ordenación (MMR + enfriamiento de artistas). Dart puro.
- `lib/dj/recommendations.dart`: recomendador clásico por afinidad (favoritos,
  playlists, historial) y `DjFilters`. Sigue alimentando Inicio y la vista DJ.
- `lib/library/library_database.dart`: base vectorial persistente (SQLite/drift).
- `AppController`: registra señales, coordina la recarga y la cola.

## Vectores de canciones

Cada canción se convierte en un vector de 256 dimensiones mediante *feature
hashing* (FNV-1a de 32 bits, con signo) y se normaliza (L2). Rasgos y pesos:

- Artistas: el principal 1,0 y los colaboradores 0,7. Se separan por `feat.`,
  `ft.`, `featuring`, `&`, `,`, `;` y ` x `; también `(feat. X)` del título.
- Álbum 0,5 (si existe y no es igual al título). Géneros reales 0,8 cada uno.
- Palabras del título 0,25 cada una, sin ruido («official video», «lyrics»,
  «letra», «audio», «hd», «remastered»…) ni palabras del nombre del artista.

Las colisiones de hash son posibles y aceptadas: es una aproximación.

## Base vectorial

Esquema 2 de la base (`aurora.sqlite`). La migración desde el esquema 1 solo
crea tablas nuevas y conserva los datos existentes:

- `track_vectors(track_key PK, track JSON, dims, vector BLOB Float32,
  updated_at)`: se guardan como máximo 5000 filas (las más recientes).
- `taste_profile(id = 1, dims, vector BLOB, updated_at)`: último perfil.

API: `upsertTrackVectors`, `nearestTracks(consulta, k, exclude)` con similitud
coseno y `readTasteProfile`/`saveTasteProfile`. La búsqueda de vecinos recorre
todas las filas en Dart (fuerza bruta): suficiente para miles de canciones.

Se incrustan una vez por sesión: toda la biblioteca (favoritos, playlists,
historial y lo reproducido), cada canción con señal de salto/finalización y
cada resultado de búsqueda, de «Buscar novedades» y del descubrimiento del DJ.

## Señales y perfil

Solo se usan señales observadas:

- Favorito: +3,0. Pertenencia a playlists: +1,5. No tienen fecha: no decaen.
- Historial reciente (posición `i`): `+0,8 / (1 + i/4)`; no registra frecuencia.
- Finalización (la pista llegó al final): +1,0 × decaimiento.
- Salto (el usuario pulsó «siguiente» antes de 30 s o del 30 % de la pista):
  −1,5 × decaimiento. Avanzar más tarde no genera ninguna señal.
- Decaimiento temporal de eventos: `0,5^(edad / 14 días)`.

Los eventos se guardan en `SharedPreferences` (`djEvents`, formato
`tipo|milisegundos|id`, últimos 500). El perfil es la suma ponderada de los
vectores de esas canciones, normalizada; se recalcula en cada recarga.

## Candidatos

1. Recomendaciones locales clásicas (hasta 24).
2. Vecinos más cercanos en la base vectorial al perfil (k = 40) y a la canción
   actual (k = 20). Sin «Incluir novedades» solo se usan canciones de la
   biblioteca.
3. Con «Incluir novedades»: hasta 2 búsquedas por recarga construidas desde el
   perfil (artistas, géneros y álbumes con más peso, alternados). Una consulta
   no se repite en la misma sesión del DJ. Los resultados se incrustan y pasan
   por la misma ordenación.

## Ordenación

`puntuación = 0,55·coseno(perfil, c) + 0,25·prior + 0,20·coseno(actual, c)
− 0,35 (escuchada entre las últimas 20) − 0,30 (artista saltado en los últimos
30 eventos)`. El *prior* refleja la posición en su lista de origen: locales
`0,6/(1 + i/5)`, búsquedas `0,5/(1 + i/5)`, vecinos `0,3/(1 + i/10)`.

Se excluyen siempre: la canción actual, todo lo que ya está en la cola o fue
añadido por el DJ en esta sesión (identidad por ID, URL canónica y URI de
Spotify, `recommendationTrackKeys`), lo que no es reproducible y lo que
rechazan los `DjFilters` (las exclusiones siempre prevalecen).

La selección es voraz con MMR (λ = 0,7): `0,7·puntuación − 0,3·máxima
similitud con lo ya elegido`, con enfriamiento de artistas: nunca el mismo
artista dos veces seguidas y como máximo dos por cada diez canciones (contando
la cola pendiente). Si todos los artistas restantes están en enfriamiento se
permite una única elección por recarga, para que una biblioteca de un solo
artista no detenga el DJ.

Cada elección conserva un motivo breve: «Porque escuchaste X», «Parecido a tus
favoritos», «De tus favoritos», «Porque escuchas a X», «Por tu gusto por X» o
el motivo del recomendador clásico. El panel DJ muestra el siguiente motivo.

## Nuevas y ya oídas

Cada tanda mezcla pistas nuevas con pistas que el usuario ya conoce (todo lo de
la biblioteca: historial, favoritos y listas). Cuota de ya oídas por modo
(`djHeardShare`): Descubrir 30 %, Energía 35 %, Por hora y ánimo 35 %, Relax
40 %; el resto son nuevas. El reparto es determinista (`djWantHeard`): la tanda
empieza por una nueva y alterna; si no queda de la clase que toca, entra la
otra. Una pista ya oída se enfría `djHeardCooldown` (3 h) y además no entra si
está entre las últimas 20 reproducidas ni si ya está en la cola de esta
sesión; las nuevas siguen con la ventana de 7 días de la memoria
anti-repetición. La cuota se aplica en el motor (`SessionContext.heardShare`,
la Jam no la usa) y en `rankDjCandidates`. El perfil local sigue mandando en
la puntuación; la coherencia de artista (`coherenceGate`, umbral
`djRelatedThreshold` 0,55, peso `djCoherenceWeight` 1,2) filtra lo no
relacionado con la semilla tanto en el motor como en `rankDjCandidates`.

## Variedad de artistas

Ninguna cola generada se llena con un solo artista: nunca el mismo artista
seguido, máximo 2 de cada 9 en el DJ, tope de ~20 % por tanda en el motor y de
~30 % (3 de 10) en el relleno automático de la cola (`_fillQueue`). La regla
solo se relaja, y solo para esa pista, cuando no queda otra alternativa. No
existe aún un modo «solo este artista». Al tocar una pista a mano suena la
elegida primero y la cola de recomendaciones se conserva (el DJ sigue activo).

## Iniciar el DJ

`AppController.startDjSession` (envoltura de `startPersonalDj`) fija el modo,
arranca con lo local o la pista actual y, sin semilla local, pide una tanda al
motor (radio de YouTube/Spotify). Las pantallas DJ y Para ti usan
`DjSessionCard`: estado «DJ activo · modo», selector de modo, «Iniciar DJ» y
«Detener DJ». Con una Jam activa el botón queda deshabilitado.

## Cola

- Al iniciar, el DJ llena hasta unas 20 canciones pendientes; después recarga
  cuando quedan menos de 10 (`kQueueLookahead`). Solo añade al final: no toca la canción actual ni lo
  que eligió el usuario.
- Autoplay: si la cola se termina con el DJ activo, recarga y continúa.
- Contadores de generación descartan resultados tardíos al detener el DJ o
  cambiar filtros. Pausar no descarta la recarga, pero no reanuda.

## Filtros

`DjFilters` acepta inclusiones `artists`, `trackIds`, `genres` y exclusiones
`excludedArtists`, `excludedTrackIds`, `excludedGenres`. Una inclusión vacía no
restringe esa dimensión. Las exclusiones siempre prevalecen. Artistas y géneros
usan coincidencia exacta normalizada; canciones usan su ID exacto.
`AppController.setDjFilters` los persiste (`djFilters`), invalida búsquedas
pendientes y descarta novedades. El encolado manual no está limitado por ellos.
`Track.genres` guarda solo géneros reales; no se infieren.

## Limitaciones

- Sin señales (biblioteca nueva) el perfil está vacío y manda el orden local.
- El hashing no entiende sonido ni letra: dos canciones parecidas con metadatos
  distintos no se reconocen como similares.
- Las búsquedas dependen del proveedor; sin red se usa solo la biblioteca.
- Pruebas: `test/dj_ai_test.dart` (proveedores simulados, base en memoria).
  No se valida la calidad musical con usuarios reales.

`importSpotifyMetadataMatch(metadata, match, play: false)` conserva metadatos
de Spotify tomando el audio de una coincidencia de YouTube elegida por el
usuario; nunca reproduce audio de Spotify.
