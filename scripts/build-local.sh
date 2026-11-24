#!/usr/bin/env bash
# 本机构建 + 测试一条龙，并按「编译一次算一次构建」的口径计数。
#
#   bash scripts/build-local.sh            # 配置 + 编译 + ctest
#   bash scripts/build-local.sh --no-test  # 只编译
#
# Windows 走 MinGW（需要把 mingw64/bin 加进 PATH），macOS / Linux 用系统编译器。
# 计数的两处：编译结束记一次 local，ctest 结束记一次 test；失败也记，result=failed。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/native"
RUN_TEST=1
[ "${1:-}" = "--no-test" ] && RUN_TEST=0

bump() { python "$ROOT/scripts/bump-build.py" --source "$1" --result "$2" --note "$3" >/dev/null || true; }

echo "=== 配置 ==="
cmake -S "$ROOT" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Debug || { bump local failed "cmake 配置失败"; exit 1; }

echo "=== 编译 ==="
if cmake --build "$BUILD"; then
  bump local success "cmake --build 全量"
else
  bump local failed "cmake --build 全量"
  exit 1
fi

if [ "$RUN_TEST" = "1" ]; then
  echo "=== 测试 ==="
  if ctest --test-dir "$BUILD" --output-on-failure; then
    bump test success "ctest 三套件"
  else
    bump test failed "ctest 三套件"
    exit 1
  fi
fi

python "$ROOT/scripts/bump-build.py" --show
