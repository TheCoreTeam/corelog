# ClangdCudaCompileDb

一个 CMake 模块，将 CMake/nvcc 生成的 `compile_commands.json` 转换为 clang-tooling 友好的编译数据库。这让 `clangd` 和 `clang-tidy` 在混合 C++/CUDA 项目中正确工作。

## 问题

CMake 配合 CUDA 生成的 `compile_commands.json` 使用 `nvcc` 作为编译器。然而 `clangd` 和 `clang-tidy` 只能消费 `clang++` 风格的命令。nvcc 标志如 `--generate-code=`、`-gencode=`、`--extended-lambda`、`-Xcompiler` 和 `--options-file` 不被 clang++ 理解，会导致错误。

更糟的是，传统方法通过 `POST_BUILD` 钩子生成转换后的数据库意味着 **如果编译失败，clangd 完全拿不到数据库**。当你最需要代码补全、导航和诊断的时候——即在修复损坏代码时——它们却不可用。

## 解决方案

本模块提供 **三种独立方式** 生成 clang-tooling 数据库，确保无论构建状态如何，clangd 始终拥有有效的编译数据库：

| 触发方式 | 时机 | 是否需要编译成功？ |
|---|---|---|
| **配置时预生成** | 在 `cmake` 重新配置时 | 否 |
| **`generate_clangd_db` 目标** | 通过构建命令按需生成 | 否 |
| **`POST_BUILD` 钩子** | 在附加的目标构建完成后 | 是 |

对于 `.cu` 文件，nvcc 命令被重写为带适当 CUDA 标志（`-x cuda`、`--cuda-host-only`）的 clang++ 命令。其他文件经过少量清理后透传（例如移除 `-fopenmp`）。响应文件（`--options-file`）被内联展开。CUDA 包含路径在 `CUDA::cudart` 可用时自动检测。

### 工作流程

```
首次使用:
  cmake -G Ninja -B build .   -> 生成 compile_commands.json (CMake 原生)
  cmake --build build         -> POST_BUILD 钩子生成 clang-tooling 数据库

代码损坏 / 编译失败:
  cmake --build build --target generate_clangd_db
                              -> 仍可生成 clang-tooling 数据库，clangd 正常工作

修改了 CMakeLists.txt:
  cmake -G Ninja -B build .   -> 配置时预生成刷新数据库
```

## 快速开始

运行时只需要 `cmake/` 和 `scripts/`。最小化引入布局：

```
third_party/cmake-clangd-cuda/
├── cmake/
│   ├── ClangdCudaCompileDb.cmake
│   └── clangd.in
└── scripts/
    └── nvcc_to_clang_compile_db.py
```

在 `project()` 和 `find_package(CUDAToolkit)` **之后** 引入模块，然后对每个目标调用 `clangd_cuda_attach()`：

```cmake
cmake_minimum_required(VERSION 3.20)

project(my_project LANGUAGES CXX CUDA)

find_package(CUDAToolkit REQUIRED)

include("${CMAKE_CURRENT_SOURCE_DIR}/third_party/cmake-clangd-cuda/cmake/ClangdCudaCompileDb.cmake")

add_executable(my_target src/main.cpp src/kernel.cu)
target_link_libraries(my_target PRIVATE CUDA::cudart)

clangd_cuda_attach(my_target)
```

该模块强制启用 `CMAKE_EXPORT_COMPILE_COMMANDS`，因此请在任何 `add_executable` / `add_library` **之前** 引入它。如果模块加载时目标已存在，将发出 CMake 警告，且这些目标不会出现在 `compile_commands.json` 中。

然后使用 Ninja 构建：

```bash
cmake -G Ninja -B build .
cmake --build build --target my_target
```

生成的 `.clangd` 配置将 clangd 指向 `build/clang-tooling/compile_commands.json`。

### 编译失败时

如果代码编译不通过，`POST_BUILD` 钩子不会运行。改用独立目标：

```bash
cmake --build build --target generate_clangd_db
```

或者简单地重新运行 `cmake -G Ninja -B build .`——在重新配置时，如果 `compile_commands.json` 已从之前的构建中存在，模块会预生成 clang-tooling 数据库。

## 配置

在 `include(ClangdCudaCompileDb)` **之前** 设置这些变量：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `CLANGD_CUDA_SOURCE_DB` | `${PROJECT_BINARY_DIR}/compile_commands.json` | 输入编译数据库 |
| `CLANGD_CUDA_OUTPUT_DIR` | `${PROJECT_BINARY_DIR}/clang-tooling` | 输出目录 |
| `CLANGD_CUDA_REPO_ROOT` | `${PROJECT_SOURCE_DIR}` | 仓库根目录（用于相对路径报告） |
| `CLANGD_CUDA_EXTRA_INCLUDE_DIRS` | *从 `CUDA::cudart` 自动检测* | CUDA 头文件的额外包含目录 |
| `CLANGD_CUDA_PATH` | *自动检测* | 传给 clang 的 CUDA toolkit 根目录 `--cuda-path=…`；CUDA 内置函数（`threadIdx`、`blockIdx`、`cudaConfigureCall` 等）需要此参数 |
| `CLANGD_CUDA_CLANG_CXX` | `""` | clang++ 可执行文件的显式路径 |
| `CLANGD_CUDA_ENABLE_CLANGD_CONFIG` | `ON` | 是否生成 `.clangd` 配置文件 |
| `CLANGD_CUDA_CLANGD_CONFIG_PATH` | `${PROJECT_SOURCE_DIR}/.clangd` | `.clangd` 的写入位置 |

## 公开 API

### `clangd_cuda_attach(<target> ...)`

为每个目标附加 `POST_BUILD` 钩子。钩子在目标成功构建后重新生成 clang-tooling 数据库。请在创建目标**之后**调用。

### `generate_clangd_db` 目标

由模块始终创建。按需构建它以重新生成数据库，无需编译成功：

```bash
cmake --build build --target generate_clangd_db
```

适用场景：
- 项目暂时无法编译
- 修改了 `CMakeLists.txt`，想在构建前刷新路径/标志
- 希望 CI 在不链接或运行测试的情况下产出数据库

## 常见问题

**Q: 为什么配置时预生成只在重新配置时有效，首次 `cmake` 不行？**

CMake 在生成阶段写入 `compile_commands.json`，而生成阶段发生在模块运行的配置阶段*之后*。首次配置时源数据库尚不存在，因此预生成被跳过。在后续 `cmake` 运行时文件已存在，因此预生成立即触发。

**Q: 生成的 `.clangd` 文件应该提交到版本控制吗？**

是的——`.clangd` 包含项目特定设置（编译数据库路径），应该提交。它在配置时生成一次，除非修改 CMake 变量否则不会变化。

**Q: 生成数据库需要安装 CUDA 吗？**

转换本身不需要——脚本只是重写 JSON。但 clangd 需要解析 CUDA 头文件来构建索引，因此需要 CUDA 包含路径。模块在 `CUDA::cudart` 可用时自动检测此路径。

**Q: 为什么用 Ninja 而不是 Unix Makefiles？**

CMake 的 `Unix Makefiles` 生成器不会为 `.cu` 文件输出 `compile_commands.json` 条目——只输出常规 C/C++ 源文件。没有这些条目，模块就没有源数据可转换，clangd 也就无法索引 CUDA 代码。而 `Ninja` 生成器会为所有源类型（包括 `.cu`）输出条目。这是 CMake 的限制，不是本模块可以绕过的。
