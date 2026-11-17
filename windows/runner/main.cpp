
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <atlbase.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace
{
  constexpr wchar_t kAppUserModelId[] = L"RST.Dolapdere.Contracts";

  constexpr wchar_t kSingleInstanceMutexName[] =
      L"Local\\RST.Dolapdere.Contracts.SingleInstance";

  constexpr wchar_t kFlutterWindowClassName[] =
      L"FLUTTER_RUNNER_WIN32_WINDOW";

  // Uygulamanın mevcut penceresini bulur ve öne getirir.
  void ActivateExistingWindow()
  {
    HWND existingWindow = nullptr;

    // İlk örnek henüz penceresini oluşturmamış olabilir.
    for (int attempt = 0; attempt < 40; ++attempt)
    {
      existingWindow = FindWindowW(kFlutterWindowClassName, nullptr);

      if (existingWindow != nullptr)
      {
        break;
      }

      Sleep(50);
    }

    if (existingWindow != nullptr)
    {
      ShowWindow(existingWindow, SW_RESTORE);
      BringWindowToTop(existingWindow);
      SetForegroundWindow(existingWindow);
    }
  }

  HRESULT EnsureStartMenuShortcut()
  {
    wchar_t executablePath[MAX_PATH];
    const DWORD pathLength =
        GetModuleFileNameW(nullptr, executablePath, MAX_PATH);

    if (pathLength == 0 || pathLength >= MAX_PATH)
    {
      return HRESULT_FROM_WIN32(GetLastError());
    }

    PWSTR programsPath = nullptr;

    HRESULT result =
        SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_CREATE, nullptr,
                             &programsPath);

    if (FAILED(result))
    {
      return result;
    }

    std::wstring shortcutPath(programsPath);
    CoTaskMemFree(programsPath);
    shortcutPath += L"\\RST Dolapdere.lnk";

    CComPtr<IShellLinkW> shellLink;

    result = shellLink.CoCreateInstance(CLSID_ShellLink);

    if (FAILED(result))
    {
      return result;
    }

    result = shellLink->SetPath(executablePath);

    if (FAILED(result))
    {
      return result;
    }

    std::wstring workingDirectory(executablePath);
    const size_t separator = workingDirectory.find_last_of(L"\\/");

    if (separator != std::wstring::npos)
    {
      workingDirectory.resize(separator);

      result = shellLink->SetWorkingDirectory(
          workingDirectory.c_str());

      if (FAILED(result))
      {
        return result;
      }
    }

    CComPtr<IPropertyStore> propertyStore;

    result = shellLink->QueryInterface(IID_PPV_ARGS(&propertyStore));

    if (FAILED(result))
    {
      return result;
    }

    PROPVARIANT appId;

    result = InitPropVariantFromString(kAppUserModelId, &appId);

    if (FAILED(result))
    {
      return result;
    }

    result = propertyStore->SetValue(PKEY_AppUserModel_ID, appId);
    PropVariantClear(&appId);

    if (FAILED(result))
    {
      return result;
    }

    // Bildirim butonlarının aktivasyon GUID'si.
    const CLSID activatorClsid = {
        0x36a5b84a,
        0x4f37,
        0x4b13,
        {0x91, 0x06, 0x42, 0x71, 0xb7, 0x86, 0xf2, 0x89}};

    PROPVARIANT activator;

    result = InitPropVariantFromCLSID(activatorClsid, &activator);

    if (FAILED(result))
    {
      return result;
    }

    result = propertyStore->SetValue(
        PKEY_AppUserModel_ToastActivatorCLSID,
        activator);

    PropVariantClear(&activator);

    if (FAILED(result))
    {
      return result;
    }

    result = propertyStore->Commit();

    if (FAILED(result))
    {
      return result;
    }

    CComPtr<IPersistFile> persistFile;

    result = shellLink->QueryInterface(IID_PPV_ARGS(&persistFile));

    if (FAILED(result))
    {
      return result;
    }

    return persistFile->Save(shortcutPath.c_str(), TRUE);
  }

} // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  // Tek örnek kontrolü.
  HANDLE singleInstanceMutex = CreateMutexW(
      nullptr,
      TRUE,
      kSingleInstanceMutexName);

  if (singleInstanceMutex == nullptr)
  {
    OutputDebugStringW(
        L"RST Dolapdere could not create the single-instance mutex.\n");

    return EXIT_FAILURE;
  }

  if (GetLastError() == ERROR_ALREADY_EXISTS)
  {
    // Uygulama zaten çalışıyor.
    ActivateExistingWindow();

    CloseHandle(singleInstanceMutex);
    return EXIT_SUCCESS;
  }

  // Konsol bağlantısı.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // COM başlat.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);

  const HRESULT shortcutResult = EnsureStartMenuShortcut();

  if (FAILED(shortcutResult))
  {
    OutputDebugStringW(
        L"RST Dolapdere could not register its Start menu notification shortcut.\n");
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(
      std::move(command_line_arguments));

  FlutterWindow window(project);

  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);

  if (!window.Create(L"RST Dolapdere", origin, size))
  {
    ::CoUninitialize();
    CloseHandle(singleInstanceMutex);

    return EXIT_FAILURE;
  }

  window.SetQuitOnClose(true);
  window.SetMinimizeToTray(true);

  // Windows mesaj döngüsü.
  ::MSG msg;

  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  CloseHandle(singleInstanceMutex);

  return EXIT_SUCCESS;
}
