#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

inline UINT GetSingleInstanceActivateMessage() {
  static const UINT message = ::RegisterWindowMessageW(
      L"com.sein.chaoxingapp.activate-existing-window");
  return message;
}

#endif  // RUNNER_SINGLE_INSTANCE_H_
