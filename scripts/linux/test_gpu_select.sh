#!/usr/bin/env bash
# Pruebas de linux/runner/gpu_select.cc: ChooseEglVendor, FindEglVendorJson y HasMesaRenderNode.
# No llama a ApplyGpuSelection (toca el entorno real). Autocontenido: el programa de prueba
# y los arboles falsos de /etc, /usr y /sys viven en un directorio temporal.
# Codigo 0 si todo pasa; distinto de 0 si algo falla.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$REPO/linux/runner/gpu_select.cc"
INC="$REPO/linux/runner"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/test_gpu_select.cc" <<'CPP'
// Pruebas de linux/runner/gpu_select.cc (ChooseEglVendor, FindEglVendorJson, HasMesaRenderNode).
// No llama a ApplyGpuSelection. Los arboles falsos de /etc, /usr y /sys viven bajo el
// directorio que recibe como argumento (creado y borrado por el script bash).
#include "gpu_select.h"

#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <functional>
#include <string>
#include <vector>

namespace {

int g_ok = 0;
int g_fail = 0;
std::string g_root;

void Report(bool ok, const std::string& name, const std::string& got,
            const std::string& want, const char* file, int line) {
  if (ok) {
    ++g_ok;
    return;
  }
  ++g_fail;
  std::printf("FALLO [%s] %s:%d\n  esperado: %s\n  obtenido: %s\n",
              name.c_str(), file, line, want.c_str(), got.c_str());
}

#define EXPECT_STR(name, got, want) \
  Report((got) == (want), (name), (got), (want), __FILE__, __LINE__)
#define EXPECT_BOOL(name, got, want)                            \
  Report((got) == (want), (name), (got) ? "true" : "false",      \
         (want) ? "true" : "false", __FILE__, __LINE__)

void MakeDirs(const std::string& path) {
  for (size_t i = 1; i <= path.size(); ++i) {
    if (i == path.size() || path[i] == '/') {
      mkdir(path.substr(0, i).c_str(), 0755);  // Si ya existe, da igual.
    }
  }
}

std::string Parent(const std::string& path) {
  return path.substr(0, path.find_last_of('/'));
}

void WriteFile(const std::string& path) {
  MakeDirs(Parent(path));
  FILE* f = std::fopen(path.c_str(), "w");
  if (f != nullptr) {
    std::fputs("{}\n", f);
    std::fclose(f);
  }
}

void Symlink(const std::string& target, const std::string& link) {
  MakeDirs(Parent(link));
  symlink(target.c_str(), link.c_str());
}

std::string CaseRoot(const std::string& name) {
  const std::string dir = g_root + "/" + name;
  MakeDirs(dir);
  return dir;
}

// Entrada "auto" de referencia: Wayland, NVIDIA y GPU Mesa presentes.
GpuSelectInput Base() {
  GpuSelectInput in;
  in.wayland = true;
  in.gdk_backend = "";
  in.user_egl_vendor = false;
  in.aurora_gpu = "";
  in.mesa_vendor_json = "/x/50_mesa.json";
  in.nvidia_vendor_present = true;
  in.mesa_render_node = true;
  return in;
}

GpuSelectInput With(const std::function<void(GpuSelectInput&)>& mod) {
  GpuSelectInput in = Base();
  mod(in);
  return in;
}

struct ChooseCase {
  const char* name;
  GpuSelectInput in;
  const char* want;
};

void TestChooseEglVendor() {
  const std::vector<ChooseCase> cases = {
      {"base: auto elige Mesa", With([](GpuSelectInput&) {}), "/x/50_mesa.json"},
      {"aurora_gpu=default -> sistema", With([](GpuSelectInput& i) { i.aurora_gpu = "default"; }), ""},
      {"aurora_gpu=system -> sistema", With([](GpuSelectInput& i) { i.aurora_gpu = "system"; }), ""},
      {"aurora_gpu=nvidia -> sistema", With([](GpuSelectInput& i) { i.aurora_gpu = "nvidia"; }), ""},
      {"aurora_gpu=NVIDIA -> sistema", With([](GpuSelectInput& i) { i.aurora_gpu = "NVIDIA"; }), ""},
      {"aurora_gpu=Default -> sistema", With([](GpuSelectInput& i) { i.aurora_gpu = "Default"; }), ""},
      {"user_egl_vendor=true -> no tocar", With([](GpuSelectInput& i) { i.user_egl_vendor = true; }), ""},
      {"user_egl_vendor=true con aurora_gpu=mesa -> no tocar",
       With([](GpuSelectInput& i) { i.user_egl_vendor = true; i.aurora_gpu = "mesa"; }), ""},
      {"wayland=false -> no tocar", With([](GpuSelectInput& i) { i.wayland = false; }), ""},
      {"wayland=false con aurora_gpu=mesa -> no tocar",
       With([](GpuSelectInput& i) { i.wayland = false; i.aurora_gpu = "mesa"; }), ""},
      {"GDK_BACKEND=x11 -> no tocar", With([](GpuSelectInput& i) { i.gdk_backend = "x11"; }), ""},
      {"GDK_BACKEND=x11,wayland -> no tocar", With([](GpuSelectInput& i) { i.gdk_backend = "x11,wayland"; }), ""},
      {"GDK_BACKEND=X11 -> no tocar", With([](GpuSelectInput& i) { i.gdk_backend = "X11"; }), ""},
      {"GDK_BACKEND=wayland -> Mesa", With([](GpuSelectInput& i) { i.gdk_backend = "wayland"; }), "/x/50_mesa.json"},
      {"GDK_BACKEND=wayland,x11 -> Mesa", With([](GpuSelectInput& i) { i.gdk_backend = "wayland,x11"; }), "/x/50_mesa.json"},
      {"mesa_vendor_json vacio -> no tocar", With([](GpuSelectInput& i) { i.mesa_vendor_json = ""; }), ""},
      {"mesa_vendor_json vacio con aurora_gpu=mesa -> no tocar",
       With([](GpuSelectInput& i) { i.mesa_vendor_json = ""; i.aurora_gpu = "mesa"; }), ""},
      {"sin NVIDIA -> no tocar", With([](GpuSelectInput& i) { i.nvidia_vendor_present = false; }), ""},
      {"sin NVIDIA con aurora_gpu=mesa -> Mesa",
       With([](GpuSelectInput& i) { i.nvidia_vendor_present = false; i.aurora_gpu = "mesa"; }), "/x/50_mesa.json"},
      {"sin GPU para Mesa -> no tocar", With([](GpuSelectInput& i) { i.mesa_render_node = false; }), ""},
      {"sin GPU para Mesa con aurora_gpu=mesa -> Mesa",
       With([](GpuSelectInput& i) { i.mesa_render_node = false; i.aurora_gpu = "mesa"; }), "/x/50_mesa.json"},
      {"sin GPU para Mesa con aurora_gpu=MESA -> Mesa",
       With([](GpuSelectInput& i) { i.mesa_render_node = false; i.aurora_gpu = "MESA"; }), "/x/50_mesa.json"},
      {"aurora_gpu=foo se comporta como auto -> Mesa", With([](GpuSelectInput& i) { i.aurora_gpu = "foo"; }), "/x/50_mesa.json"},
      {"aurora_gpu=foo sin NVIDIA -> no tocar",
       With([](GpuSelectInput& i) { i.aurora_gpu = "foo"; i.nvidia_vendor_present = false; }), ""},
  };
  for (const ChooseCase& c : cases) {
    EXPECT_STR(c.name, ChooseEglVendor(c.in), std::string(c.want));
  }
}

void TestFindEglVendorJson() {
  const std::string etc = "/etc/glvnd/egl_vendor.d/";
  const std::string usr = "/usr/share/glvnd/egl_vendor.d/";
  {
    const std::string root = CaseRoot("find_solo_usr");
    WriteFile(root + usr + "50_mesa.json");
    EXPECT_STR("solo en usr/share -> ruta de usr/share",
               FindEglVendorJson(root, "50_mesa.json"), root + usr + "50_mesa.json");
  }
  {
    const std::string root = CaseRoot("find_ambos");
    WriteFile(root + etc + "50_mesa.json");
    WriteFile(root + usr + "50_mesa.json");
    EXPECT_STR("en etc y usr/share -> ruta de etc",
               FindEglVendorJson(root, "50_mesa.json"), root + etc + "50_mesa.json");
  }
  {
    const std::string root = CaseRoot("find_solo_etc");
    WriteFile(root + etc + "50_mesa.json");
    EXPECT_STR("solo en etc -> ruta de etc",
               FindEglVendorJson(root, "50_mesa.json"), root + etc + "50_mesa.json");
  }
  {
    const std::string root = CaseRoot("find_ninguno");
    EXPECT_STR("en ningun sitio -> vacio", FindEglVendorJson(root, "50_mesa.json"), std::string());
  }
  {
    const std::string root = CaseRoot("find_otro_nombre");
    WriteFile(root + usr + "50_mesa.json");
    EXPECT_STR("nombre distinto -> vacio", FindEglVendorJson(root, "10_nvidia.json"), std::string());
  }
  {
    const std::string root = CaseRoot("find_etc_ilegible");
    WriteFile(root + etc + "50_mesa.json");
    WriteFile(root + usr + "50_mesa.json");
    if (geteuid() == 0) {
      std::printf("omitido (root ignora permisos de lectura): etc ilegible\n");
    } else {
      chmod((root + etc + "50_mesa.json").c_str(), 0000);
      EXPECT_STR("etc no legible -> cae a usr/share",
                 FindEglVendorJson(root, "50_mesa.json"), root + usr + "50_mesa.json");
    }
  }
}

void AddDrmNode(const std::string& root, const std::string& node,
                const std::string& driver) {
  const std::string dev = root + "/sys/class/drm/" + node + "/device";
  MakeDirs(dev);
  if (!driver.empty()) {
    Symlink("../../../bus/pci/drivers/" + driver, dev + "/driver");
  }
}

void TestHasMesaRenderNode() {
  {
    const std::string root = CaseRoot("drm_solo_nvidia");
    AddDrmNode(root, "renderD128", "nvidia");
    EXPECT_BOOL("solo nvidia -> false", HasMesaRenderNode(root), false);
  }
  {
    const std::string root = CaseRoot("drm_nvidia_i915");
    AddDrmNode(root, "renderD128", "nvidia");
    AddDrmNode(root, "renderD129", "i915");
    EXPECT_BOOL("nvidia + i915 -> true", HasMesaRenderNode(root), true);
  }
  {
    const std::string root = CaseRoot("drm_amdgpu");
    AddDrmNode(root, "renderD128", "amdgpu");
    EXPECT_BOOL("amdgpu -> true", HasMesaRenderNode(root), true);
  }
  {
    const std::string root = CaseRoot("drm_xe");
    AddDrmNode(root, "renderD128", "xe");
    EXPECT_BOOL("xe -> true", HasMesaRenderNode(root), true);
  }
  {
    const std::string root = CaseRoot("drm_radeon");
    AddDrmNode(root, "renderD128", "radeon");
    EXPECT_BOOL("radeon -> true", HasMesaRenderNode(root), true);
  }
  {
    const std::string root = CaseRoot("drm_nouveau");
    AddDrmNode(root, "renderD128", "nouveau");
    EXPECT_BOOL("nouveau -> true", HasMesaRenderNode(root), true);
  }
  {
    const std::string root = CaseRoot("drm_card0_i915");
    AddDrmNode(root, "card0", "i915");
    EXPECT_BOOL("card0 (no renderD*) con i915 -> false", HasMesaRenderNode(root), false);
  }
  {
    const std::string root = CaseRoot("drm_sin_sys");
    EXPECT_BOOL("sin /sys/class/drm -> false", HasMesaRenderNode(root), false);
  }
  {
    const std::string root = CaseRoot("drm_sin_driver");
    AddDrmNode(root, "renderD128", "");
    EXPECT_BOOL("renderD128 sin enlace driver -> false", HasMesaRenderNode(root), false);
  }
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "uso: %s <directorio-temporal>\n", argv[0]);
    return 2;
  }
  g_root = argv[1];
  TestChooseEglVendor();
  TestFindEglVendorJson();
  TestHasMesaRenderNode();
  if (g_fail == 0) {
    std::printf("%d casos OK\n", g_ok);
    return 0;
  }
  std::printf("%d casos OK, %d FALLAN\n", g_ok, g_fail);
  return 1;
}
CPP

mkdir -p "$WORK/raiz"
g++ -std=c++17 -Wall -Wextra -I"$INC" -o "$WORK/test_gpu_select" "$WORK/test_gpu_select.cc" "$SRC"
"$WORK/test_gpu_select" "$WORK/raiz"
