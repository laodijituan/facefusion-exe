FaceFusion 绿色便携版（Windows x64）
====================================

启动
----
双击 FaceFusion.exe。
程序会在本机启动一个网页控制台，并自动打开浏览器
（地址通常是 http://127.0.0.1:7860 ）。关掉黑色命令行窗口即退出。

第一次启动会比较慢：需要联网下载模型（约 1.5 GB～3 GB），
下载位置是本目录下的 .assets\models\ ，下次启动直接复用。
如果公司网络/校园网连不上 github / huggingface，可以手动把 onnx 模型
放进 .assets\models\ 目录再启动。

目录说明
--------
FaceFusion.exe  主程序
ffmpeg.exe      视频编解码（已内置，无需另装）
ffprobe.exe     视频信息读取（已内置）
curl.exe        模型下载器（已内置）
.assets\        模型缓存（可整个复制到别的机器上复用）
.jobs\          任务队列数据
output\         网页界面导出的结果
facefusion\     源码（保留明文，方便审计/打补丁）
BUILD-INFO.txt  本次构建的版本信息
使用说明.txt    本文件

命令行用法（高级）
------------------
FaceFusion.exe run                      启动网页界面
FaceFusion.exe run --open-browser       启动并自动开浏览器（默认行为）
FaceFusion.exe headless-run -s face.jpg -t video.mp4 -o out.mp4
FaceFusion.exe batch-run -s face.jpg -t "clips\*.mp4" -o "out"
FaceFusion.exe force-download           只下载模型
FaceFusion.exe benchmark --resolution 512x512 --cycle-count 5
FaceFusion.exe -h                       查看全部参数

显卡 / 加速
-----------
* 启动后在界面 Execution 区域选择执行提供者：
  - NVIDIA 独显：CUDAExecutionProvider
  - 任意显卡/核显：DirectMLExecutionProvider（需 directml 版构建）
  - 纯 CPU：CPUExecutionProvider（很慢）
* CUDA 版需要 NVIDIA 驱动 ≥ 550（RTX 20 系及以上建议）。若本包未内置
  CUDA 运行时，请自行安装 CUDA 12.x + cuDNN 9.x。
* 显存 6 GB 以下建议：人脸增强关闭或换小模型、输出分辨率 1080p 以内。

常见问题
--------
1) 杀毒软件报警 / 文件被删
   PyInstaller 打包的程序常被误报，可加入白名单后重新解压。
   本包不含任何加壳或混淆代码，facefusion\ 目录里就是明文源码，可自行核对。

2) 端口被占用
   设环境变量 GRADIO_SERVER_PORT=7861 后再运行。

3) 中文路径 / 长路径报错
   Windows 路径长度限制 260 字符。建议把整个文件夹放在 C:\FaceFusion 这类短路径下，
   或在组策略里开启 Win32 长路径支持。

4) 提示 ffmpeg is not installed
   确认本目录下有 ffmpeg.exe 和 ffprobe.exe（不要只放到 PATH 里）。

5) 第一次跑模型检查很久 / 卡在 downloading
   是正常下载，看进度条；网络差时可以先跑 FaceFusion.exe force-download 单独下。

法律与伦理提醒
--------------
换脸技术涉及肖像权、个人信息保护与著作权。请仅对自己拥有权利或已获得
明确授权的素材使用；不得用于制作、传播伪造他人身份的影像（可能触犯刑法、
选举罢免法、性私密影像相关法规等）。使用者自行承担全部法律责任。

本程序基于 FaceFusion（https://github.com/facefusion/facefusion，
OpenRAIL-AS 许可）打包，沿袭其许可证条款：不得用于违法、侵权、
生成未经同意的私密影像等用途。
