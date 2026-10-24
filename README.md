# FaceFusion → Windows 便携版 EXE 构建套件

把 FaceFusion 官方源码打成 **免安装、解压即用的 Windows x64 程序**（含 ffmpeg、模型下载器、CUDA 运行时）。
不需要目标机器装 Python、不需要 CUDA 工具链（GPU 版可内置）。

---

## 0. 先说清楚：为什么不是"打包 roop-windows-GUI 的源码"

你给的 `zhaoyun0071/roop-windows-GUI` 仓库里**没有源码**。我查了 V8.6 那个 commit 的完整文件树：

```
README.md    ui.png    ui2.png      ← 就这 3 个文件
```

V8.3 / V8.5 / V8.6 三个 tag 指向同一个 commit（`a7f06d1`，提交信息只有 "Update README.md"）。
作者只发布打包好的 7z（放在夸克网盘 / 腾讯文档），自己写的那个中文启动界面是闭源的。

它里面的换脸内核本来就是开源的，所以本套件改为**直接构建上游 FaceFusion**——功能比 V8.6 内置的那版更新、更全，而且源码可审计、可复现、不会被塞私货。

| 对比 | roop-win-GUI V8.6 | 本套件 |
|---|---|---|
| 源码 | 无（闭源 GUI + 网盘 exe） | 上游 FaceFusion，明文保留在包里 |
| 可复现 | 否 | 是（钉 commit，哈希可查） |
| 恶意代码风险 | 无法审计 | 可逐行核对 |
| 功能 | FaceFusion 3.x + rope + VisoMaster | FaceFusion 最新版（换脸/唇形/年龄/表情/高清/抠背景/上色） |

> 构建用的上游版本：`facefusion/facefusion` commit **`7247081`**（2026-09-30，`fix coreml under recent macos`）。
> 想跟最新版就改 `-Ref` 参数（分支/tag/commit 都行）；想锁定旧版就把 commit 写死。

---

## 1. 文件清单

| 文件 | 作用 |
|---|---|
| `launcher.py` | EXE 入口：设置 PATH、切工作目录、默认 `run --open-browser`、准备 `.assets/.jobs/output` |
| `facefusion.spec` | PyInstaller 配置：把源码当数据落地（FaceFusion 靠运行时列目录发现插件）、收集 gradio 前端、onnxruntime provider、可选 CUDA DLL |
| `build_windows.ps1` | 一键构建：拉源码 → venv → 装依赖 → 下 ffmpeg → PyInstaller → 打包 zip + SHA256 |
| `requirements-build.txt` | 构建期依赖锁定（PyInstaller 6.22.3） |
| `bundle-readme.txt` | 会被复制进成品包，改名 `使用说明.txt` |
| `.github/workflows/build-exe.yml` | 云端编译：Windows runner 上并行出 `cpu` / `cuda12` 两个包 |

---

## 2. 路线 A：GitHub Actions 云编译（推荐，你的电脑什么都不用装）

1. 在 GitHub 新建一个仓库（private 也行），把这 6 个文件按原目录结构推上去：

```bash
git init
git add .
git commit -m "facefusion windows exe builder"
git branch -M main
git remote add origin https://github.com/<你的账号>/<仓库名>.git
git push -u origin main
```

2. 打开仓库 → **Actions** 标签页 → 左侧 `build-windows-exe` → 右侧 **Run workflow**。
   * `ref`：默认 `7247081`，想跟最新就填 `master`
   * `bundle_cuda`：默认 `true`（把 cuDNN9/cuBLAS12/cudart12 打进包，用户不用装 CUDA）

3. 大约 **25–45 分钟**后，在工作流页面底部 **Artifacts** 下载：
   * `FaceFusion-cpu-win64.zip`
   * `FaceFusion-cuda12-win64.zip`（含 `SHA256SUMS.txt`）

> 免费账号的 Actions 在私有仓库每月有 2000 分钟额度；Windows runner 按 2 倍计费，一次双包构建约消耗 60–90 分钟额度。公开仓库不计量。

### 不想建仓库？

GitHub 网页上也能操作：新建仓库 → `Add file` → `Create new file`，路径写 `.github/workflows/build-exe.yml` 粘贴内容，再同样上传其余文件；然后 Actions 里 Run workflow。

---

## 3. 路线 B：本机 Windows 构建

前提：**Python 3.12 x64**（[python.org](https://www.python.org/downloads/windows/)，务必勾选 Add to PATH）、Git、约 12 GB 空闲磁盘。

```powershell
# 在解压后的目录里，PowerShell 窗口
Set-ExecutionPolicy -Scope Process Bypass -Force

# NVIDIA 显卡（内置 CUDA 运行时，包更大但开箱能 GPU 跑）
.\build_windows.ps1 -Variant cuda12

# 只要 CPU 版（约 700 MB）
.\build_windows.ps1 -Variant cpu

# 显卡版但不想内置 CUDA（用户自行安装 CUDA 12.x + cuDNN 9）
.\build_windows.ps1 -Variant cuda12 -NoCudaRuntime
```

产物：

```
.work\dist\FaceFusion\            ← 直接双击 FaceFusion.exe 就能用
.work\dist\FaceFusion-cuda12-win64-7247081.zip
.work\dist\SHA256SUMS.txt
```

---

## 4. 构建变体

| Variant | onnxruntime 包 | 适用 | 成品体积（压缩后约） |
|---|---|---|---|
| `cpu` | `onnxruntime 1.30.0` | 没独显 / 兜底 | 220–300 MB |
| `cuda12` | `onnxruntime-gpu 1.24.4` | RTX 20/30/40/50 系，CUDA 12 + cuDNN 9 | 有内置 CUDA ≈ 1.6–2.2 GB；无内置 ≈ 350 MB |
| `cuda13` | `onnxruntime-gpu 1.30.0` | 驱动已更新到 CUDA 13 的环境 | 同上 |
| `directml` | `onnxruntime-directml 1.24.4` | AMD / Intel 核显 | ≈ 350 MB |

GPU 版要求：NVIDIA 驱动 ≥ 550（新版 ORT 要求较新的驱动）。内置 CUDA 运行时后**不需要**单独装 CUDA Toolkit。

> 注意：只有 `cuda12` 会自动内置 CUDA 运行时（cuDNN/cuBLAS/cudart 的 pip wheel 有 win_amd64 版，已确认可下载）。
> `cuda13` / `directml` 变体不会内置，`cuda13` 需要你在目标机自行安装 CUDA 13。

---

## 5. 成品怎么用

解压 zip 到 **短路径**（比如 `C:\FaceFusion`，别放桌面深目录，Windows 260 字符路径限制会炸），双击 `FaceFusion.exe`：

1. 第一次启动会自动下载模型 **1.5–3 GB** 到 `.assets\models\`，看清进度条，别以为卡死；
2. 浏览器自动打开 `http://127.0.0.1:7860`，就是换脸界面；
3. `Execution` 区块里选执行提供者：NVIDIA 选 `CUDAExecutionProvider`，AMD/Intel 用 `DirectML`，都没有就 `CPU`；
4. 换脸：`Face Swapper` 处理器 + 源图（脸）+ 目标视频/图片 → START。

命令行（高级用法）：

```bat
FaceFusion.exe run                       :: 开界面
FaceFusion.exe headless-run -s face.jpg -t video.mp4 -o out.mp4
FaceFusion.exe batch-run -s face.jpg -t "clips\*.mp4" -o out
FaceFusion.exe force-download            :: 只下模型，适合提前备好离线包
FaceFusion.exe benchmark --resolution 512x512 --cycle-count 5
FaceFusion.exe -h
```

离线部署：在能上网的机器上跑一次 `force-download`，把 `.assets` 整个目录拷到目标机器，就完全不用联网。

---

## 6. 已做的验证

本套件不是"写完就交"，下面的验证是在沙箱 Linux 环境用同一份 `launcher.py` + `facefusion.spec` 实跑过的（PyInstaller 逻辑跨平台一致，Windows 侧只是 DLL 和 ffmpeg.exe 不同）：

- ✅ PyInstaller 构建成功，产物 **678 MB**（CPU 版，Linux 等价尺寸）
- ✅ `FaceFusion --help` 正常，13 个命令、11 个处理器、4 个 UI 布局全部被正确枚举（这一步最容易翻车：FaceFusion 靠列目录找插件，PyInstaller 默认打包会全部丢失，本 spec 用"源码当数据 + hiddenimports 全量收集"解决）
- ✅ `FaceFusion run` 启动 Gradio，`curl http://127.0.0.1:7860/` 返回 **HTTP 200**
- ✅ 模型自动下载并落盘到 `<exe目录>/.assets/models/`（1.4 GB，跨次启动复用）
- ✅ 无 `_internal` 夹层的"老式 onedir"扁平布局，源码明文可见（`facefusion\` 目录）

两个踩过的坑（已在 spec 里修掉，你自己改的时候注意）：

1. `contents_directory='.'` 必须写在 **`EXE()`** 里，写在 `COLLECT()` 里会被静默忽略，结果还是 `_internal/` 布局，导致相对路径全废；
2. `collect_submodules('facefusion')` 在 FaceFusion 未 pip 安装时返回空列表 → 打包出来所有处理器都 "could not be loaded"。必须先 `sys.path.insert(0, SRC)` 再收集，并额外做一次 `os.walk` 兜底。

---

## 7. 排错

| 现象 | 原因 / 处理 |
|---|---|
| Actions 上 "No space left on device" | 已内置 `free-disk-space`；若仍失败，把 `bundle_cuda` 设为 false，或删掉 matrix 里的 `cpu` |
| 成品被杀毒软件删掉 | PyInstaller 通病误报。包内 `facefusion\` 是明文源码，可自证；加白名单或对 zip 做代码签名 |
| 启动报 `ffmpeg is not installed` | `ffmpeg.exe` / `ffprobe.exe` 必须和 `FaceFusion.exe` 同目录（脚本已自动复制） |
| 中文用户名 / 中文路径报错 | 设 `PYTHONUTF8=1`（已内置）；输出路径尽量用英文 |
| GPU 列表里没有 CUDA | 驱动太旧，或用了 `cpu` 版；`cuda12` 版启动日志里会打印可用 provider |
| 端口占用 | `set GRADIO_SERVER_PORT=7861` 再启动 |
| 想减体积 | `-NoCudaRuntime`、删 `excludes` 以外的无用包、或改用 `directml` |

---

## 8. 合规提醒

FaceFusion 采用 **OpenRAIL-AS** 许可：允许使用，但禁止违法、侵权、生成未经同意的私密影像等用途。在台湾地区，制作或散布伪造他人面貌的影像可能涉及刑法伪变造文书、性隐私影像相关法规、选罢法（对手候选人）等；也涉及肖像权与个人资料保护法。请只对自有或已获授权的素材使用，并对产物负责。

自用、明确授权、内部测试是一回事；公开传播、冒充他人、涉及未成年人完全是另一回事——后者不要碰。
