#ifndef RUNNER_GPU_SELECT_H_
#define RUNNER_GPU_SELECT_H_

#include <string>

// Elección del controlador OpenGL (EGL) en equipos con dos GPU.
//
// En Wayland, libglvnd carga todos los proveedores EGL instalados. En un
// portátil Intel/AMD + NVIDIA eso mete en el proceso las bibliotecas de NVIDIA
// (unos 115 MB de RSS; despiertan además la GPU dedicada) aunque Flutter acabe
// dibujando con Mesa en la integrada. Si hay una GPU que Mesa maneja por
// hardware, se le pide a libglvnd que use solo Mesa.
//
// AURORA_GPU=default (o nvidia) deja el comportamiento del sistema;
// AURORA_GPU=mesa lo fuerza aunque no se detecte la GPU integrada.

struct GpuSelectInput {
  bool wayland = false;              // WAYLAND_DISPLAY definido.
  std::string gdk_backend;           // GDK_BACKEND (vacío si no está).
  bool user_egl_vendor = false;      // __EGL_VENDOR_LIBRARY_FILENAMES/_DIRS.
  std::string aurora_gpu;            // AURORA_GPU (vacío si no está).
  std::string mesa_vendor_json;      // Ruta del json de Mesa ("" si no hay).
  bool nvidia_vendor_present = false;  // Hay json de NVIDIA para EGL.
  bool mesa_render_node = false;     // Hay una GPU con driver de Mesa.
};

// Ruta del json que poner en __EGL_VENDOR_LIBRARY_FILENAMES, o "" para no
// tocar nada.
std::string ChooseEglVendor(const GpuSelectInput& input);

// Busca `name` en los directorios de proveedores EGL de libglvnd bajo `root`
// ("" = raíz real). Devuelve la ruta completa o "".
std::string FindEglVendorJson(const std::string& root, const std::string& name);

// ¿Hay un nodo /sys/class/drm/renderD* con un driver que Mesa use por
// hardware (i915, xe, amdgpu, radeon, nouveau)? `root` como arriba.
bool HasMesaRenderNode(const std::string& root);

// Lee el entorno real, decide y ajusta las variables del proceso. Llamar al
// principio de main(), antes de iniciar GTK.
void ApplyGpuSelection();

#endif  // RUNNER_GPU_SELECT_H_
