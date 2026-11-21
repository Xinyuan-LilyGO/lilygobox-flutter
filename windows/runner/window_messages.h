#ifndef RUNNER_WINDOW_MESSAGES_H_
#define RUNNER_WINDOW_MESSAGES_H_

#include <windows.h>

namespace lilygobox {
namespace messages {
enum : UINT {
  kTrayMessage = WM_APP + 71,
  kDismissMenuMessage,
  kMenuHostReady,
  kMenuHostAction,
  kMenuHostPainted,
  kLayoutChangedMessage,
  kOpenMenuMessage,
  kToggleMaximizeMessage,
  kMenuHostPrepared,
  kBeginReaderMode,
  kPrepareMenuMessage,
  kShowAfterFirstFrame,
};
}  // namespace messages
}  // namespace lilygobox

#endif
