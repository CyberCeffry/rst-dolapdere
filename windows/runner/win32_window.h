
#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <shellapi.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window.
class Win32Window
{
public:
  struct Point
  {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size
  {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  bool Create(const std::wstring &title,
              const Point &origin,
              const Size &size);

  bool Show();

  void Destroy();

  void SetChildContent(HWND content);

  HWND GetHandle();

  void SetQuitOnClose(bool quit_on_close);

  RECT GetClientArea();

  // System tray controls.
  void SetMinimizeToTray(bool enabled);
  void HideToTray();
  void RestoreFromTray();
  void ExitFromTray();

protected:
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  virtual bool OnCreate();
  virtual void OnDestroy();

private:
  friend class WindowClassRegistrar;

  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  static Win32Window *GetThisFromHandle(HWND const window) noexcept;

  static void UpdateTheme(HWND const window);

  // System tray helpers.
  bool AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();

  bool quit_on_close_ = false;
  bool minimize_to_tray_ = false;
  bool tray_icon_added_ = false;
  bool is_exiting_ = false;

  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;

  NOTIFYICONDATAW tray_icon_data_ = {};
};
#endif // RUNNER_WIN32_WINDOW_H_
