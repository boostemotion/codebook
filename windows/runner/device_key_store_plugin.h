#ifndef RUNNER_DEVICE_KEY_STORE_PLUGIN_H_
#define RUNNER_DEVICE_KEY_STORE_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

class DeviceKeyStorePlugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
};

#endif  // RUNNER_DEVICE_KEY_STORE_PLUGIN_H_
