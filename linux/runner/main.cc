#include <malloc.h>
#include <stdlib.h>

#include "my_application.h"

int main(int argc, char** argv) {
#ifdef __GLIBC__
  // glibc crea hasta 8 arenas de malloc por núcleo para los hilos del motor de
  // Flutter, Skia y Rust, y casi nunca devuelve al sistema lo que se libera en
  // ellas: el RSS sube cientos de MB sin uso real. Dos arenas bastan para esta
  // carga. Si el usuario define MALLOC_ARENA_MAX, manda su valor.
  if (getenv("MALLOC_ARENA_MAX") == nullptr) {
    mallopt(M_ARENA_MAX, 2);
  }
#endif
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
