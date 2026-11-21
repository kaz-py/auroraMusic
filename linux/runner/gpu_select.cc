#include "gpu_select.h"

#include <dirent.h>
#include <limits.h>
#include <stdlib.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>

namespace {

const char* const kVendorDirs[] = {"/etc/glvnd/egl_vendor.d",
                                   "/usr/share/glvnd/egl_vendor.d"};

std::string Lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return std::tolower(c); });
  return value;
}

std::string Env(const char* name) {
  const char* value = getenv(name);
  return value == nullptr ? std::string() : std::string(value);
}

bool Exists(const std::string& path) { return access(path.c_str(), R_OK) == 0; }

}  // namespace

std::string ChooseEglVendor(const GpuSelectInput& input) {
  const std::string mode = Lower(input.aurora_gpu);
  if (mode == "default" || mode == "system" || mode == "nvidia") return "";
  if (input.user_egl_vendor) return "";
  if (!input.wayland) return "";
  // GDK_BACKEND=x11 (o "x11,wayland"): GTK usa GLX, no EGL.
  if (Lower(input.gdk_backend).rfind("x11", 0) == 0) return "";
  if (input.mesa_vendor_json.empty()) return "";
  if (mode == "mesa") return input.mesa_vendor_json;
  // Sin NVIDIA no hay nada que ahorrar; sin GPU para Mesa, Mesa dibujaría por
  // software (llvmpipe), que es peor que cargar NVIDIA.
  if (!input.nvidia_vendor_present || !input.mesa_render_node) return "";
  return input.mesa_vendor_json;
}

std::string FindEglVendorJson(const std::string& root,
                              const std::string& name) {
  for (const char* dir : kVendorDirs) {
    const std::string path = root + dir + "/" + name;
    if (Exists(path)) return path;
  }
  return "";
}

bool HasMesaRenderNode(const std::string& root) {
  const std::string drm = root + "/sys/class/drm";
  DIR* dir = opendir(drm.c_str());
  if (dir == nullptr) return false;
  bool found = false;
  while (dirent* entry = readdir(dir)) {
    const std::string name = entry->d_name;
    if (name.rfind("renderD", 0) != 0) continue;
    char target[PATH_MAX];
    const std::string link = drm + "/" + name + "/device/driver";
    const ssize_t len = readlink(link.c_str(), target, sizeof(target) - 1);
    if (len <= 0) continue;
    target[len] = '\0';
    std::string driver = target;
    const size_t slash = driver.find_last_of('/');
    if (slash != std::string::npos) driver = driver.substr(slash + 1);
    if (driver == "i915" || driver == "xe" || driver == "amdgpu" ||
        driver == "radeon" || driver == "nouveau") {
      found = true;
      break;
    }
  }
  closedir(dir);
  return found;
}

void ApplyGpuSelection() {
  GpuSelectInput input;
  input.wayland = !Env("WAYLAND_DISPLAY").empty();
  input.gdk_backend = Env("GDK_BACKEND");
  input.user_egl_vendor = getenv("__EGL_VENDOR_LIBRARY_FILENAMES") != nullptr ||
                          getenv("__EGL_VENDOR_LIBRARY_DIRS") != nullptr;
  input.aurora_gpu = Env("AURORA_GPU");
  input.mesa_vendor_json = FindEglVendorJson("", "50_mesa.json");
  input.nvidia_vendor_present = !FindEglVendorJson("", "10_nvidia.json").empty();
  input.mesa_render_node = HasMesaRenderNode("");

  const std::string vendor = ChooseEglVendor(input);
  if (vendor.empty()) return;
  setenv("__EGL_VENDOR_LIBRARY_FILENAMES", vendor.c_str(), 1);
  // Con __GLX_VENDOR_LIBRARY_NAME=nvidia, libepoxy carga igualmente
  // libGLX_nvidia y el resto del driver al abrir libGL. En Wayland Aurora no usa
  // GLX, así que se quita solo para este proceso.
  unsetenv("__GLX_VENDOR_LIBRARY_NAME");
}
