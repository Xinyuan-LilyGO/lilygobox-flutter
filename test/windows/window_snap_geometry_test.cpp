#include "../../windows/runner/window_snap_geometry.h"

#include <cassert>

int main() {
  const RECT work{0, 0, 2560, 1400};
  assert(lilygobox::HasSnappedGeometry({0, 0, 1280, 1400}, work, 2));
  assert(lilygobox::HasSnappedGeometry({1280, 0, 2560, 1400}, work, 2));
  assert(lilygobox::HasSnappedGeometry({-2, -2, 1280, 1402}, work, 2));
  // 普通靠边和未铺满工作区的小窗口不能误判为贴靠。
  assert(!lilygobox::HasSnappedGeometry({0, 150, 1280, 1000}, work, 2));
  assert(!lilygobox::HasSnappedGeometry({100, 0, 1380, 1400}, work, 2));
  assert(!lilygobox::HasSnappedGeometry({0, 0, 900, 600}, work, 2));
  // 上下半屏、四个角和全工作区都使用直角外框。
  assert(lilygobox::HasSnappedGeometry({0, 0, 2560, 700}, work, 2));
  assert(lilygobox::HasSnappedGeometry({0, 700, 2560, 1400}, work, 2));
  assert(lilygobox::HasSnappedGeometry({0, 0, 1280, 700}, work, 2));
  assert(lilygobox::HasSnappedGeometry({1280, 0, 2560, 700}, work, 2));
  assert(lilygobox::HasSnappedGeometry({0, 700, 1280, 1400}, work, 2));
  assert(lilygobox::HasSnappedGeometry({1280, 700, 2560, 1400}, work, 2));
  assert(lilygobox::HasSnappedGeometry(work, work, 2));
  // 最大化实测的系统边框会超出工作区，按 DPI 对应边框容差判断。
  assert(lilygobox::HasSnappedGeometry({-9, -9, 1289, 1409}, work, 12));
  assert(!lilygobox::HasSnappedGeometry({-30, -30, 1280, 1400}, work, 12));
  // 副屏负坐标及左侧任务栏工作区同样按当前显示器判断。
  assert(lilygobox::HasSnappedGeometry({-1920, 0, -960, 1040},
                                     {-1920, 0, 0, 1040}, 2));
  assert(lilygobox::HasSnappedGeometry({80, 0, 1320, 1440},
                                     {80, 0, 2560, 1440}, 2));
}
