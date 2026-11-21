#!/usr/bin/env bash
# Pruebas de linux/runner/tray_linux.cc: StatusNotifierItem, dbusmenu y registro
# en un StatusNotifierWatcher falso. Corre en un bus de sesion privado
# (dbus-run-session). Si falta dbus-run-session o gdbus imprime "omitido" y sale 0.
# Codigo 0 si todo pasa; distinto de 0 si algo falla.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$REPO/linux/runner/tray_linux.cc"
INC="$REPO/linux/runner"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! command -v dbus-run-session >/dev/null 2>&1 || ! command -v gdbus >/dev/null 2>&1; then
  echo "omitido: falta dbus-run-session o gdbus"
  exit 0
fi

cat >"$WORK/test_tray.cc" <<'CPP'
// Pruebas de linux/runner/tray_linux.cc: StatusNotifierItem, dbusmenu y registro
// en un StatusNotifierWatcher falso. Todo corre en el hilo principal: las llamadas
// de cliente son asincronas y se bombea el contexto por defecto de GLib hasta
// recibir la respuesta, que es donde el tray sirve sus metodos.
// Necesita bus de sesion: lo aporta dbus-run-session desde el script bash.
#include "tray_linux.h"

#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace {

using Var = std::unique_ptr<GVariant, void (*)(GVariant*)>;

Var Envuelve(GVariant* v) { return Var(v, g_variant_unref); }

const char kItemRuta[] = "/StatusNotifierItem";
const char kItemIface[] = "org.kde.StatusNotifierItem";
const char kMenuRuta[] = "/MenuBar";
const char kMenuIface[] = "com.canonical.dbusmenu";

int g_ok = 0;
int g_fail = 0;
GDBusConnection* g_cliente = nullptr;

void ExpectStr(const std::string& nombre, const std::string& obtenido,
               const std::string& esperado, const char* archivo, int linea) {
  if (obtenido == esperado) {
    ++g_ok;
    return;
  }
  ++g_fail;
  std::printf("FALLO [%s] %s:%d\n  esperado: %s\n  obtenido: %s\n",
              nombre.c_str(), archivo, linea, esperado.c_str(), obtenido.c_str());
}

#define EXPECT_STR(nombre, obtenido, esperado) \
  ExpectStr((nombre), (obtenido), (esperado), __FILE__, __LINE__)
#define EXPECT_BOOL(nombre, obtenido, esperado)                       \
  ExpectStr((nombre), ((obtenido) ? "true" : "false"),                 \
            ((esperado) ? "true" : "false"), __FILE__, __LINE__)

int Resumen() {
  if (g_fail == 0) {
    std::printf("%d casos OK\n", g_ok);
    return 0;
  }
  std::printf("%d casos OK, %d FALLAN\n", g_ok, g_fail);
  return 1;
}

// ---- Bombeo y llamadas D-Bus asincronas -----------------------------------

bool Esperar(const std::function<bool()>& listo, gint64 ms = 3000) {
  const gint64 fin = g_get_monotonic_time() + ms * 1000;
  while (!listo()) {
    if (g_get_monotonic_time() > fin) return false;
    g_main_context_iteration(nullptr, FALSE);
    g_usleep(1000);
  }
  return true;
}

struct Respuesta {
  bool listo = false;
  GVariant* valor = nullptr;
  std::string error;
};

void AlRecibir(GObject* origen, GAsyncResult* res, gpointer datos) {
  auto* r = static_cast<Respuesta*>(datos);
  GError* err = nullptr;
  r->valor = g_dbus_connection_call_finish(G_DBUS_CONNECTION(origen), res, &err);
  if (err != nullptr) {
    r->error = err->message;
    g_error_free(err);
  }
  r->listo = true;
}

struct Resultado {
  bool ok = false;
  std::string error;
  Var valor{nullptr, g_variant_unref};
};

Resultado Llamar(GDBusConnection* bus, const char* destino, const char* ruta,
                 const char* iface, const char* metodo, GVariant* params) {
  // Si expira, la memoria se deja sin liberar: una respuesta tardia escribiria en ella.
  auto* r = new Respuesta();
  g_dbus_connection_call(bus, destino, ruta, iface, metodo, params, nullptr,
                         G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, AlRecibir, r);
  Resultado out;
  if (!Esperar([r] { return r->listo; })) {
    out.error = std::string("sin respuesta a ") + metodo;
    return out;
  }
  out.ok = r->error.empty();
  out.error = r->error;
  out.valor.reset(r->valor);
  delete r;
  return out;
}

bool TieneDueno(const std::string& nombre) {
  Resultado r = Llamar(g_cliente, "org.freedesktop.DBus", "/org/freedesktop/DBus",
                       "org.freedesktop.DBus", "NameHasOwner",
                       g_variant_new("(s)", nombre.c_str()));
  if (!r.ok) return false;
  gboolean dueno = FALSE;
  g_variant_get(r.valor.get(), "(b)", &dueno);
  return dueno != FALSE;
}

// ---- Representacion de valores --------------------------------------------

std::string Describe(GVariant* v) {
  if (g_variant_is_of_type(v, G_VARIANT_TYPE_STRING) ||
      g_variant_is_of_type(v, G_VARIANT_TYPE_OBJECT_PATH)) {
    return g_variant_get_string(v, nullptr);
  }
  if (g_variant_is_of_type(v, G_VARIANT_TYPE_BOOLEAN)) {
    return g_variant_get_boolean(v) ? "true" : "false";
  }
  if (g_variant_is_of_type(v, G_VARIANT_TYPE_UINT32)) {
    return std::to_string(g_variant_get_uint32(v));
  }
  return std::string("<tipo ") + g_variant_get_type_string(v) + ">";
}

// Propiedad de un objeto (org.freedesktop.DBus.Properties.Get). Null si falla.
Var Propiedad(const std::string& destino, const char* ruta, const char* iface,
              const char* prop) {
  Resultado r = Llamar(g_cliente, destino.c_str(), ruta,
                       "org.freedesktop.DBus.Properties", "Get",
                       g_variant_new("(ss)", iface, prop));
  if (!r.ok) return Envuelve(nullptr);
  GVariant* dentro = nullptr;
  g_variant_get(r.valor.get(), "(v)", &dentro);
  return Envuelve(dentro);
}

std::string Valor(const std::string& destino, const char* ruta, const char* iface,
                  const char* prop) {
  Var v = Propiedad(destino, ruta, iface, prop);
  return v ? Describe(v.get()) : std::string("<sin propiedad>");
}

std::string Hex(const guchar* d, gsize n) {
  std::string out;
  for (gsize i = 0; i < n; ++i) {
    char b[4];
    std::snprintf(b, sizeof b, "%02x", d[i]);
    if (i > 0) out += ' ';
    out += b;
  }
  return out;
}

std::string Unir(const std::vector<std::string>& v) {
  std::string out;
  for (const std::string& s : v) {
    if (!out.empty()) out += ",";
    out += s;
  }
  return out;
}

// ---- Icono temporal (16x16 RGBA) ------------------------------------------

bool CreaIcono(const std::string& dir) {
  mkdir(dir.c_str(), 0755);
  GdkPixbuf* pb = gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, 16, 16);
  if (pb == nullptr) return false;
  gdk_pixbuf_fill(pb, 0xff0000ffu);  // Rojo opaco en todo el icono.
  guchar* px = gdk_pixbuf_get_pixels(pb);
  px[4] = 0x00;  // Pixel (1,0): verde con alfa 128.
  px[5] = 0xff;
  px[6] = 0x00;
  px[7] = 0x80;
  GError* err = nullptr;
  const bool ok = gdk_pixbuf_save(pb, (dir + "/icono.png").c_str(), "png", &err, NULL);
  if (err != nullptr) g_error_free(err);
  g_object_unref(pb);
  return ok;
}

// ---- Watcher falso (org.kde.StatusNotifierWatcher) ------------------------

const char kWatcherXml[] = R"XML(
<node>
  <interface name="org.kde.StatusNotifierWatcher">
    <method name="RegisterStatusNotifierItem">
      <arg name="service" type="s" direction="in"/>
    </method>
  </interface>
</node>)XML";

struct Watcher {
  GDBusNodeInfo* info = nullptr;
  guint reg = 0;
  guint owner = 0;
  std::vector<std::string> registrados;
};
Watcher g_watcher;

void WatcherCall(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                 const gchar* metodo, GVariant* params,
                 GDBusMethodInvocation* inv, gpointer) {
  if (std::string(metodo) == "RegisterStatusNotifierItem") {
    const gchar* servicio = nullptr;
    g_variant_get(params, "(&s)", &servicio);
    g_watcher.registrados.push_back(servicio);
    g_dbus_method_invocation_return_value(inv, nullptr);
  } else {
    g_dbus_method_invocation_return_error(inv, G_DBUS_ERROR,
                                          G_DBUS_ERROR_UNKNOWN_METHOD,
                                          "Metodo desconocido");
  }
}

const GDBusInterfaceVTable kWatcherVTable = {WatcherCall, nullptr, nullptr,
                                             {nullptr}};

void InicioWatcher() {
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  g_watcher.info = g_dbus_node_info_new_for_xml(kWatcherXml, nullptr);
  g_watcher.reg = g_dbus_connection_register_object(
      bus, "/StatusNotifierWatcher", g_watcher.info->interfaces[0], &kWatcherVTable,
      nullptr, nullptr, nullptr);
  g_watcher.owner = g_bus_own_name_on_connection(
      bus, "org.kde.StatusNotifierWatcher", G_BUS_NAME_OWNER_FLAGS_NONE, nullptr,
      nullptr, nullptr, nullptr);
}

// ---- Callback del tray y lectura del menu ---------------------------------

struct Registro {
  std::vector<AuroraTrayCommand> comandos;
};

void AlComando(AuroraTrayCommand comando, gpointer datos) {
  static_cast<Registro*>(datos)->comandos.push_back(comando);
}

std::string Cadena(const std::vector<AuroraTrayCommand>& cs) {
  if (cs.empty()) return "(ninguno)";
  std::string out;
  for (AuroraTrayCommand c : cs) {
    if (!out.empty()) out += ",";
    switch (c) {
      case AURORA_TRAY_SHOW: out += "SHOW"; break;
      case AURORA_TRAY_PLAY_PAUSE: out += "PLAY_PAUSE"; break;
      case AURORA_TRAY_NEXT: out += "NEXT"; break;
      case AURORA_TRAY_PREVIOUS: out += "PREVIOUS"; break;
      case AURORA_TRAY_QUIT: out += "QUIT"; break;
    }
  }
  return out;
}

struct Layout {
  bool ok = false;
  std::string error;
  guint32 revision = 0;
  Var raiz{nullptr, g_variant_unref};  // (ia{sv}av)
};

Layout PedirLayout(const std::string& destino, int padre, int profundidad) {
  Resultado r = Llamar(g_cliente, destino.c_str(), kMenuRuta, kMenuIface,
                       "GetLayout",
                       g_variant_new("(ii@as)", padre, profundidad,
                                     g_variant_new_strv(nullptr, 0)));
  Layout l;
  l.ok = r.ok;
  l.error = r.error;
  if (!r.ok) return l;
  Var rev(g_variant_get_child_value(r.valor.get(), 0), g_variant_unref);
  l.revision = g_variant_get_uint32(rev.get());
  l.raiz.reset(g_variant_get_child_value(r.valor.get(), 1));
  return l;
}

// Hijo i de un "av" ya desenvuelto (cada elemento es un "(ia{sv}av)").
Var Hijo(GVariant* av, gsize i) {
  Var envoltorio(g_variant_get_child_value(av, i), g_variant_unref);
  return Var(g_variant_get_variant(envoltorio.get()), g_variant_unref);
}

Var Nodo(GVariant* raiz, int id) {
  if (raiz == nullptr) return Envuelve(nullptr);
  Var hijos(g_variant_get_child_value(raiz, 2), g_variant_unref);
  for (gsize i = 0; i < g_variant_n_children(hijos.get()); ++i) {
    Var nodo = Hijo(hijos.get(), i);
    Var idv(g_variant_get_child_value(nodo.get(), 0), g_variant_unref);
    if (g_variant_get_int32(idv.get()) == id) return nodo;
  }
  return Envuelve(nullptr);
}

std::string IdsHijos(GVariant* raiz) {
  if (raiz == nullptr) return "<sin layout>";
  Var hijos(g_variant_get_child_value(raiz, 2), g_variant_unref);
  std::vector<std::string> ids;
  for (gsize i = 0; i < g_variant_n_children(hijos.get()); ++i) {
    Var nodo = Hijo(hijos.get(), i);
    Var idv(g_variant_get_child_value(nodo.get(), 0), g_variant_unref);
    ids.push_back(std::to_string(g_variant_get_int32(idv.get())));
  }
  return Unir(ids);
}

// Campo de la entrada id: "<no existe>", "<ausente>" o su valor en texto.
std::string Campo(GVariant* raiz, int id, const char* clave) {
  Var nodo = Nodo(raiz, id);
  if (!nodo) return "<no existe>";
  Var props(g_variant_get_child_value(nodo.get(), 1), g_variant_unref);
  Var v(g_variant_lookup_value(props.get(), clave, nullptr), g_variant_unref);
  if (!v) return "<ausente>";
  return Describe(v.get());
}

// ---- Comprobaciones de StatusNotifierItem ---------------------------------

void ComprobaPixmap(const std::string& destino) {
  Var pix = Propiedad(destino, kItemRuta, kItemIface, "IconPixmap");
  const bool tipo_ok =
      pix && g_variant_is_of_type(pix.get(), G_VARIANT_TYPE("a(iiay)"));
  EXPECT_BOOL("IconPixmap: tipo a(iiay)", tipo_ok, true);
  if (!tipo_ok) return;
  const gsize entradas = g_variant_n_children(pix.get());
  EXPECT_STR("IconPixmap: una sola entrada", std::to_string(entradas), "1");
  if (entradas != 1) return;
  Var e(g_variant_get_child_value(pix.get(), 0), g_variant_unref);
  Var w(g_variant_get_child_value(e.get(), 0), g_variant_unref);
  Var h(g_variant_get_child_value(e.get(), 1), g_variant_unref);
  Var px(g_variant_get_child_value(e.get(), 2), g_variant_unref);
  EXPECT_STR("IconPixmap: ancho 16", std::to_string(g_variant_get_int32(w.get())), "16");
  EXPECT_STR("IconPixmap: alto 16", std::to_string(g_variant_get_int32(h.get())), "16");
  gsize n = 0;
  const auto* d = static_cast<const guchar*>(g_variant_get_fixed_array(px.get(), &n, 1));
  EXPECT_STR("IconPixmap: 1024 bytes", std::to_string(n), "1024");
  if (n < 8) return;
  EXPECT_STR("IconPixmap: primer pixel A,R,G,B = ff ff 00 00", Hex(d, 4), "ff ff 00 00");
  EXPECT_STR("IconPixmap: segundo pixel (alfa 128) A,R,G,B = 80 00 ff 00",
             Hex(d + 4, 4), "80 00 ff 00");
}

Var EventoParams(int id, const char* tipo) {
  return Envuelve(g_variant_new("(isvu)", id, tipo, g_variant_new_string(""),
                                static_cast<guint32>(0)));
}

// ---- Senal LayoutUpdated --------------------------------------------------

struct Senales {
  std::vector<guint32> revs;
};

void AlLayoutUpdated(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                     const gchar*, GVariant* params, gpointer datos) {
  guint32 rev = 0;
  gint32 padre = 0;
  g_variant_get(params, "(ui)", &rev, &padre);
  static_cast<Senales*>(datos)->revs.push_back(rev);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "uso: %s <directorio-temporal>\n", argv[0]);
    return 2;
  }
  const std::string raiz = argv[1];
  const std::string iconos = raiz + "/iconos";
  g_cliente = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (g_cliente == nullptr || !CreaIcono(iconos)) {
    std::printf("FALLO de preparacion: bus de sesion o icono PNG\n");
    return 1;
  }

  // ---- 1. Anfitrion de bandeja --------------------------------------------
  EXPECT_BOOL("host: sin watcher -> FALSE", aurora_tray_host_available(), false);
  InicioWatcher();
  EXPECT_BOOL("host: con watcher -> TRUE",
              Esperar([] { return aurora_tray_host_available() != FALSE; }), true);

  Registro reg;
  AuroraTray* tray = aurora_tray_new(iconos.c_str(), "icono", AlComando, &reg);
  EXPECT_BOOL("new: no NULL con bus de sesion", tray != nullptr, true);
  if (tray == nullptr) return Resumen();
  EXPECT_BOOL("host: TRUE con el tray creado", aurora_tray_host_available() != FALSE,
              true);

  // ---- 2. Nombre y registro en el watcher ---------------------------------
  const std::string nombre =
      "org.kde.StatusNotifierItem-" + std::to_string(getpid()) + "-1";
  Esperar([] { return !g_watcher.registrados.empty(); });
  EXPECT_STR("registro: el watcher recibe el nombre del item",
             Unir(g_watcher.registrados), nombre);
  EXPECT_BOOL("nombre: poseido en el bus",
              Esperar([&] { return TieneDueno(nombre); }), true);

  // ---- 3. Propiedades de StatusNotifierItem -------------------------------
  EXPECT_STR("prop Id", Valor(nombre, kItemRuta, kItemIface, "Id"), "aurora-music");
  EXPECT_STR("prop Category", Valor(nombre, kItemRuta, kItemIface, "Category"),
             "ApplicationStatus");
  EXPECT_STR("prop Status", Valor(nombre, kItemRuta, kItemIface, "Status"), "Active");
  EXPECT_STR("prop IconName", Valor(nombre, kItemRuta, kItemIface, "IconName"), "icono");
  EXPECT_STR("prop IconThemePath", Valor(nombre, kItemRuta, kItemIface, "IconThemePath"),
             iconos);
  EXPECT_STR("prop Title sin cancion", Valor(nombre, kItemRuta, kItemIface, "Title"),
             "Aurora Music");
  EXPECT_STR("prop ItemIsMenu", Valor(nombre, kItemRuta, kItemIface, "ItemIsMenu"),
             "false");
  EXPECT_STR("prop Menu", Valor(nombre, kItemRuta, kItemIface, "Menu"), "/MenuBar");
  ComprobaPixmap(nombre);

  // ---- 4. Activate, SecondaryActivate, ContextMenu, Scroll ----------------
  auto Item = [&](const char* metodo, GVariant* params) {
    reg.comandos.clear();
    return Llamar(g_cliente, nombre.c_str(), kItemRuta, kItemIface, metodo, params);
  };
  Resultado r = Item("Activate", g_variant_new("(ii)", 0, 0));
  EXPECT_BOOL("Activate(0,0): sin error", r.ok, true);
  EXPECT_STR("Activate(0,0) -> SHOW", Cadena(reg.comandos), "SHOW");
  r = Item("SecondaryActivate", g_variant_new("(ii)", 0, 0));
  EXPECT_BOOL("SecondaryActivate(0,0): sin error", r.ok, true);
  EXPECT_STR("SecondaryActivate(0,0) -> PLAY_PAUSE", Cadena(reg.comandos), "PLAY_PAUSE");
  r = Item("ContextMenu", g_variant_new("(ii)", 0, 0));
  EXPECT_BOOL("ContextMenu(0,0): sin error", r.ok, true);
  EXPECT_STR("ContextMenu: no llama al callback", Cadena(reg.comandos), "(ninguno)");
  r = Item("Scroll", g_variant_new("(is)", 1, "vertical"));
  EXPECT_BOOL("Scroll(1,vertical): sin error", r.ok, true);
  EXPECT_STR("Scroll: no llama al callback", Cadena(reg.comandos), "(ninguno)");

  // ---- 5. com.canonical.dbusmenu ------------------------------------------
  EXPECT_STR("menu: Version = 3", Valor(nombre, kMenuRuta, kMenuIface, "Version"), "3");
  Layout lay = PedirLayout(nombre, 0, -1);
  EXPECT_BOOL("GetLayout(0,-1,[]): sin error", lay.ok, true);
  EXPECT_STR("GetLayout: hijos con ids 1..8", IdsHijos(lay.raiz.get()),
             "1,2,3,4,5,6,7,8");
  EXPECT_STR("id 1 label sin cancion", Campo(lay.raiz.get(), 1, "label"), "");
  EXPECT_STR("id 1 enabled sin cancion", Campo(lay.raiz.get(), 1, "enabled"), "false");
  EXPECT_STR("id 1 visible sin cancion", Campo(lay.raiz.get(), 1, "visible"), "false");
  EXPECT_STR("id 2 separador", Campo(lay.raiz.get(), 2, "type"), "separator");
  EXPECT_STR("id 3 label", Campo(lay.raiz.get(), 3, "label"), "Mostrar Aurora");
  EXPECT_STR("id 4 label", Campo(lay.raiz.get(), 4, "label"), "Reproducir");
  EXPECT_STR("id 5 label", Campo(lay.raiz.get(), 5, "label"), "Siguiente");
  EXPECT_STR("id 6 label", Campo(lay.raiz.get(), 6, "label"), "Anterior");
  EXPECT_STR("id 7 separador", Campo(lay.raiz.get(), 7, "type"), "separator");
  EXPECT_STR("id 8 label", Campo(lay.raiz.get(), 8, "label"), "Salir");
  Layout malo = PedirLayout(nombre, 99, -1);
  EXPECT_BOOL("GetLayout(99): da error", malo.ok, false);

  // ---- 6. Event y EventGroup ----------------------------------------------
  auto Evento = [&](int id, const char* tipo) {
    reg.comandos.clear();
    return Llamar(g_cliente, nombre.c_str(), kMenuRuta, kMenuIface, "Event",
                  EventoParams(id, tipo).release());
  };
  r = Evento(3, "clicked");
  EXPECT_BOOL("Event(3,clicked): sin error", r.ok, true);
  EXPECT_STR("Event(3,clicked) -> SHOW", Cadena(reg.comandos), "SHOW");
  Evento(4, "clicked");
  EXPECT_STR("Event(4,clicked) -> PLAY_PAUSE", Cadena(reg.comandos), "PLAY_PAUSE");
  Evento(5, "clicked");
  EXPECT_STR("Event(5,clicked) -> NEXT", Cadena(reg.comandos), "NEXT");
  Evento(6, "clicked");
  EXPECT_STR("Event(6,clicked) -> PREVIOUS", Cadena(reg.comandos), "PREVIOUS");
  Evento(8, "clicked");
  EXPECT_STR("Event(8,clicked) -> QUIT", Cadena(reg.comandos), "QUIT");
  Evento(1, "clicked");
  EXPECT_STR("Event(1,clicked): sin callback", Cadena(reg.comandos), "(ninguno)");
  Evento(4, "hovered");
  EXPECT_STR("Event(4,hovered): sin callback", Cadena(reg.comandos), "(ninguno)");

  reg.comandos.clear();
  GVariantBuilder lote;
  g_variant_builder_init(&lote, G_VARIANT_TYPE("a(isvu)"));
  g_variant_builder_add(&lote, "(isvu)", 5, "clicked", g_variant_new_string(""),
                        static_cast<guint32>(0));
  r = Llamar(g_cliente, nombre.c_str(), kMenuRuta, kMenuIface, "EventGroup",
             g_variant_new("(@a(isvu))", g_variant_builder_end(&lote)));
  EXPECT_BOOL("EventGroup([5,clicked]): sin error", r.ok, true);
  EXPECT_STR("EventGroup([5,clicked]) -> NEXT", Cadena(reg.comandos), "NEXT");

  // ---- 7. set_playback: revision, etiquetas, Title y senal ----------------
  Senales senales;
  const guint suscripcion = g_dbus_connection_signal_subscribe(
      g_cliente, nullptr, kMenuIface, "LayoutUpdated", kMenuRuta, nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, AlLayoutUpdated, &senales, nullptr);
  TieneDueno(nombre);  // Barrera: la suscripcion ya esta en el bus.

  Layout antes = PedirLayout(nombre, 0, -1);
  aurora_tray_set_playback(tray, "Tema", "Artista", TRUE);
  Esperar([&] { return !senales.revs.empty(); });
  Layout tras = PedirLayout(nombre, 0, -1);
  EXPECT_BOOL("set_playback: la revision sube", tras.revision > antes.revision, true);
  EXPECT_STR("set_playback: una senal LayoutUpdated", std::to_string(senales.revs.size()),
             "1");
  EXPECT_STR("LayoutUpdated lleva la revision nueva",
             std::to_string(senales.revs.empty() ? 0 : senales.revs.back()),
             std::to_string(tras.revision));
  EXPECT_STR("id 4 pasa a Pausa", Campo(tras.raiz.get(), 4, "label"), "Pausa");
  EXPECT_STR("id 1 label Tema – Artista", Campo(tras.raiz.get(), 1, "label"),
             "Tema – Artista");
  EXPECT_STR("id 1 visible", Campo(tras.raiz.get(), 1, "visible"), "true");
  EXPECT_STR("id 1 sigue deshabilitado", Campo(tras.raiz.get(), 1, "enabled"), "false");
  EXPECT_STR("Title = Tema – Artista",
             Valor(nombre, kItemRuta, kItemIface, "Title"), "Tema – Artista");

  aurora_tray_set_playback(tray, "Tema", "Artista", TRUE);  // Misma llamada otra vez.
  Layout igual = PedirLayout(nombre, 0, -1);
  EXPECT_STR("repetir: la revision no sube", std::to_string(igual.revision),
             std::to_string(tras.revision));
  EXPECT_STR("repetir: sin nueva senal", std::to_string(senales.revs.size()), "1");

  aurora_tray_set_playback(tray, "Tema", "", TRUE);  // Artista vacio.
  Layout sin_artista = PedirLayout(nombre, 0, -1);
  EXPECT_BOOL("artista vacio: la revision sube", sin_artista.revision > igual.revision,
              true);
  EXPECT_STR("artista vacio: id 1 solo Tema", Campo(sin_artista.raiz.get(), 1, "label"),
             "Tema");
  EXPECT_STR("artista vacio: Title = Tema", Valor(nombre, kItemRuta, kItemIface, "Title"),
             "Tema");

  aurora_tray_set_playback(tray, "Tema", "", FALSE);  // Pausado.
  Layout pausado = PedirLayout(nombre, 0, -1);
  EXPECT_STR("playing=FALSE: id 4 vuelve a Reproducir",
             Campo(pausado.raiz.get(), 4, "label"), "Reproducir");

  aurora_tray_set_playback(tray, nullptr, nullptr, FALSE);  // Sin cancion.
  Layout vacio = PedirLayout(nombre, 0, -1);
  EXPECT_STR("sin cancion: Title = Aurora Music",
             Valor(nombre, kItemRuta, kItemIface, "Title"), "Aurora Music");
  EXPECT_STR("sin cancion: id 1 label vacia", Campo(vacio.raiz.get(), 1, "label"), "");
  EXPECT_STR("sin cancion: id 1 invisible", Campo(vacio.raiz.get(), 1, "visible"), "false");
  g_dbus_connection_signal_unsubscribe(g_cliente, suscripcion);

  // ---- 8. aurora_tray_free ------------------------------------------------
  aurora_tray_free(tray);
  tray = nullptr;
  EXPECT_BOOL("free: el nombre deja de estar en el bus",
              Esperar([&] { return !TieneDueno(nombre); }), true);
  aurora_tray_free(nullptr);  // Sin excepcion: llegar aqui es el resultado.

  return Resumen();
}
CPP

g++ -std=c++17 -Wall -Wextra $(pkg-config --cflags --libs gtk+-3.0) -I"$INC" \
  -o "$WORK/test_tray" "$WORK/test_tray.cc" "$SRC"
dbus-run-session -- "$WORK/test_tray" "$WORK"
