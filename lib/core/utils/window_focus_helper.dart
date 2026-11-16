import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _FindWindowWNative =
    IntPtr Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);
typedef _FindWindowWDart =
    int Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);

typedef _IsIconicNative = Int32 Function(IntPtr hWnd);
typedef _IsIconicDart = int Function(int hWnd);

typedef _ShowWindowNative = Int32 Function(IntPtr hWnd, Int32 nCmdShow);
typedef _ShowWindowDart = int Function(int hWnd, int nCmdShow);

typedef _GetForegroundWindowNative = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();

typedef _GetWindowThreadProcessIdNative =
    Uint32 Function(IntPtr hWnd, Pointer<Uint32> lpdwProcessId);
typedef _GetWindowThreadProcessIdDart =
    int Function(int hWnd, Pointer<Uint32> lpdwProcessId);

typedef _GetCurrentThreadIdNative = Uint32 Function();
typedef _GetCurrentThreadIdDart = int Function();

typedef _AttachThreadInputNative =
    Int32 Function(Uint32 idAttach, Uint32 idAttachTo, Int32 fAttach);
typedef _AttachThreadInputDart =
    int Function(int idAttach, int idAttachTo, int fAttach);

typedef _SetForegroundWindowNative = Int32 Function(IntPtr hWnd);
typedef _SetForegroundWindowDart = int Function(int hWnd);

typedef _BringWindowToTopNative = Int32 Function(IntPtr hWnd);
typedef _BringWindowToTopDart = int Function(int hWnd);

class WindowFocusHelper {
  static void bringToFront() {
    if (!Platform.isWindows) return;

    final user32 = DynamicLibrary.open('user32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');

    final findWindow = user32
        .lookupFunction<_FindWindowWNative, _FindWindowWDart>('FindWindowW');
    final isIconic = user32.lookupFunction<_IsIconicNative, _IsIconicDart>(
      'IsIconic',
    );
    final showWindow = user32
        .lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow');
    final getForegroundWindow = user32
        .lookupFunction<_GetForegroundWindowNative, _GetForegroundWindowDart>(
          'GetForegroundWindow',
        );
    final getWindowThreadProcessId = user32
        .lookupFunction<
          _GetWindowThreadProcessIdNative,
          _GetWindowThreadProcessIdDart
        >('GetWindowThreadProcessId');
    final getCurrentThreadId = kernel32
        .lookupFunction<_GetCurrentThreadIdNative, _GetCurrentThreadIdDart>(
          'GetCurrentThreadId',
        );
    final attachThreadInput = user32
        .lookupFunction<_AttachThreadInputNative, _AttachThreadInputDart>(
          'AttachThreadInput',
        );
    final setForegroundWindow = user32
        .lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>(
          'SetForegroundWindow',
        );
    final bringWindowToTop = user32
        .lookupFunction<_BringWindowToTopNative, _BringWindowToTopDart>(
          'BringWindowToTop',
        );

    // Flutter Windows uygulamasının standart pencere sınıfı adı
    final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final hwnd = findWindow(className, nullptr);
    calloc.free(className);

    if (hwnd == 0) return;

    // 1. Pencere simge durumundaysa (minimized) eski boyutuna döndür (SW_RESTORE = 9)
    if (isIconic(hwnd) != 0) {
      showWindow(hwnd, 9);
    } else {
      // Gizliyse göster (SW_SHOW = 5)
      showWindow(hwnd, 5);
    }

    // 2. Windows'un odak çalma engelini aşarak pencereyi en öne zorla
    final fgHwnd = getForegroundWindow();
    final fgThreadId = fgHwnd != 0
        ? getWindowThreadProcessId(fgHwnd, nullptr)
        : 0;
    final currentThreadId = getCurrentThreadId();

    if (fgThreadId != 0 && fgThreadId != currentThreadId) {
      attachThreadInput(currentThreadId, fgThreadId, 1);
      setForegroundWindow(hwnd);
      bringWindowToTop(hwnd);
      attachThreadInput(currentThreadId, fgThreadId, 0);
    } else {
      setForegroundWindow(hwnd);
      bringWindowToTop(hwnd);
    }
  }
}
