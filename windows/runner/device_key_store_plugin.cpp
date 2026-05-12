#include "device_key_store_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <UserConsentVerifierInterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.UI.h>
#include <windows.h>
#include <wincrypt.h>

#include <chrono>
#include <filesystem>
#include <future>
#include <functional>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr wchar_t kAppDataDirectory[] = L"Cipherbook";
constexpr wchar_t kCacheFileName[] = L"quick_unlock.dpapi";
constexpr wchar_t kWindowsHelloPrompt[] =
    L"Use Windows Hello to unlock Cipherbook";
HWND g_auth_window = nullptr;

bool RunOnMtaBoolWithTimeout(const std::function<bool()>& work,
                             std::chrono::milliseconds timeout,
                             bool fallback) {
  std::promise<bool> promise;
  auto future = promise.get_future();
  try {
    std::thread([promise = std::move(promise), work, fallback]() mutable {
      try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
      } catch (...) {
      }
      try {
        promise.set_value(work());
      } catch (...) {
        try {
          promise.set_value(fallback);
        } catch (...) {
        }
      }
    }).detach();
    if (future.wait_for(timeout) != std::future_status::ready) {
      return fallback;
    }
    return future.get();
  } catch (...) {
    return fallback;
  }
}

std::filesystem::path CacheFilePath() {
  PWSTR local_app_data = nullptr;
  const HRESULT result =
      SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local_app_data);
  if (FAILED(result) || local_app_data == nullptr) {
    return {};
  }

  std::filesystem::path path(local_app_data);
  CoTaskMemFree(local_app_data);
  return path / kAppDataDirectory / kCacheFileName;
}

bool WriteFileBytes(const std::filesystem::path& path,
                    const std::vector<uint8_t>& bytes) {
  std::error_code error;
  std::filesystem::create_directories(path.parent_path(), error);
  if (error) {
    return false;
  }

  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }

  DWORD written = 0;
  const BOOL ok = WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
                            &written, nullptr);
  CloseHandle(file);
  return ok && written == bytes.size();
}

std::vector<uint8_t> ReadFileBytes(const std::filesystem::path& path) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return {};
  }

  LARGE_INTEGER size;
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 ||
      size.QuadPart > static_cast<LONGLONG>(1024 * 1024)) {
    CloseHandle(file);
    return {};
  }

  std::vector<uint8_t> bytes(static_cast<size_t>(size.QuadPart));
  DWORD read = 0;
  const BOOL ok = ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
                           &read, nullptr);
  CloseHandle(file);
  if (!ok || read != bytes.size()) {
    return {};
  }
  return bytes;
}

std::vector<uint8_t> ProtectBytes(const std::vector<uint8_t>& plaintext) {
  DATA_BLOB input{};
  input.pbData = const_cast<BYTE*>(plaintext.data());
  input.cbData = static_cast<DWORD>(plaintext.size());

  DATA_BLOB output{};
  if (!CryptProtectData(&input, L"Cipherbook quick unlock key", nullptr,
                        nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    return {};
  }

  std::vector<uint8_t> protected_bytes(output.pbData,
                                       output.pbData + output.cbData);
  LocalFree(output.pbData);
  return protected_bytes;
}

std::vector<uint8_t> UnprotectBytes(const std::vector<uint8_t>& protected_bytes) {
  DATA_BLOB input{};
  input.pbData = const_cast<BYTE*>(protected_bytes.data());
  input.cbData = static_cast<DWORD>(protected_bytes.size());

  DATA_BLOB output{};
  if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    return {};
  }

  std::vector<uint8_t> plaintext(output.pbData, output.pbData + output.cbData);
  LocalFree(output.pbData);
  return plaintext;
}

bool IsWindowsHelloAvailable() {
  using winrt::Windows::Security::Credentials::UI::UserConsentVerifier;
  using winrt::Windows::Security::Credentials::UI::
      UserConsentVerifierAvailability;
  return RunOnMtaBoolWithTimeout(
      []() {
        const auto availability =
            UserConsentVerifier::CheckAvailabilityAsync().get();
        return availability == UserConsentVerifierAvailability::Available;
      },
      std::chrono::milliseconds(2500),
      false);
}

HWND ResolveAuthWindow() {
  if (g_auth_window != nullptr && IsWindow(g_auth_window)) {
    return g_auth_window;
  }
  return GetForegroundWindow();
}

bool VerifyWithWindowsHello(HWND window) {
  using winrt::Windows::Foundation::IAsyncOperation;
  using winrt::Windows::Security::Credentials::UI::UserConsentVerifier;
  using winrt::Windows::Security::Credentials::UI::UserConsentVerificationResult;
  if (window == nullptr) {
    return false;
  }
  return RunOnMtaBoolWithTimeout(
      [window]() {
        auto interop = winrt::get_activation_factory<UserConsentVerifier,
                                                     IUserConsentVerifierInterop>();
        IAsyncOperation<UserConsentVerificationResult> operation{nullptr};
        winrt::check_hresult(interop->RequestVerificationForWindowAsync(
            window,
            reinterpret_cast<HSTRING>(
                winrt::get_abi(winrt::hstring(kWindowsHelloPrompt))),
            winrt::guid_of<decltype(operation)>(),
            winrt::put_abi(operation)));
        const auto verify_result = operation.get();
        return verify_result == UserConsentVerificationResult::Verified;
      },
      std::chrono::seconds(15),
      false);
}

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  const std::filesystem::path path = CacheFilePath();

  if (method == "isSupported") {
    result->Success(flutter::EncodableValue(!path.empty() &&
                                            IsWindowsHelloAvailable()));
    return;
  }

  if (method == "hasWrappedDekCache") {
    if (path.empty()) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    std::error_code error;
    const bool exists = std::filesystem::exists(path, error) && !error;
    result->Success(flutter::EncodableValue(exists));
    return;
  }

  if (path.empty()) {
    result->Error("unavailable", "Windows LocalAppData is unavailable.");
    return;
  }

  if (method == "storeWrappedDek") {
    const auto* bytes =
        std::get_if<std::vector<uint8_t>>(method_call.arguments());
    if (bytes == nullptr || bytes->empty()) {
      result->Error("invalid_argument", "Expected non-empty Uint8List.");
      return;
    }

    const std::vector<uint8_t> protected_bytes = ProtectBytes(*bytes);
    if (protected_bytes.empty() || !WriteFileBytes(path, protected_bytes)) {
      result->Error("write_failed", "Failed to store quick unlock key.");
      return;
    }
    result->Success();
    return;
  }

  if (method == "readWrappedDek") {
    auto async_result = std::move(result);
    const auto auth_window = ResolveAuthWindow();
    std::thread(
        [path, auth_window, result = std::move(async_result)]() mutable {
          const std::vector<uint8_t> protected_bytes = ReadFileBytes(path);
          if (protected_bytes.empty()) {
            result->Success(flutter::EncodableValue());
            return;
          }
          if (!VerifyWithWindowsHello(auth_window)) {
            result->Success(flutter::EncodableValue());
            return;
          }

          const std::vector<uint8_t> plaintext =
              UnprotectBytes(protected_bytes);
          if (plaintext.empty()) {
            result->Success(flutter::EncodableValue());
            return;
          }
          result->Success(flutter::EncodableValue(plaintext));
        })
        .detach();
    return;
  }

  if (method == "clear") {
    DeleteFileW(path.c_str());
    result->Success();
    return;
  }

  result->NotImplemented();
}

class DeviceKeyStorePluginImpl : public flutter::Plugin {
 public:
  explicit DeviceKeyStorePluginImpl(flutter::PluginRegistrarWindows* registrar)
      : channel_(std::make_unique<
                 flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(),
            "dev.codex.cipherbook/device_key_store",
            &flutter::StandardMethodCodec::GetInstance())) {
    if (registrar != nullptr) {
      if (auto* view = registrar->GetView(); view != nullptr) {
        g_auth_window = view->GetNativeWindow();
      }
    }
    channel_->SetMethodCallHandler(HandleMethodCall);
  }

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace

void DeviceKeyStorePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<DeviceKeyStorePluginImpl>(registrar));
}
