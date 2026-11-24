# Windows 离线语音

语音功能在 Windows 上使用 sherpa-onnx 2.0.3 本地推理，与智能体使用的对话模型、角色卡和聊天记录相互独立。模型导入后，录音识别和朗读不需要联网；发送聊天仍使用已配置的模型服务。

## 模型和音色

打开「设置 → 智能体 → 语音 → 导入模型」，直接选择官方 `.tar.bz2` 或 `.tar.zst`，不需要手动解包。每个包放一个受支持的模型，模型文件可在包的根目录或同一个子目录下。

| 用途 | 已在 Windows x64 验证的上游模型 | 所需文件 |
| --- | --- | --- |
| 中英双语识别 | [Streaming Zipformer 2023-02-20](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2) | `encoder-epoch-99-avg-1.int8.onnx`、`decoder-epoch-99-avg-1.onnx`、`joiner-epoch-99-avg-1.int8.onnx`、`tokens.txt` |
| 中文合成 | [VITS vits-zh-ll](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-vits-zh-ll.tar.bz2) | `model.onnx`、`lexicon.txt`、`tokens.txt`、`phone.fst`、`date.fst`、`number.fst` 和原始 `dict/` |

应用只安装所需文件，保持模型内部路径，不要求额外清单。模型按文件内容去重，修改文件名不影响去重。每种类型首个成功导入的模型自动成为默认模型，其余可在列表设为默认。合成模型支持试听；当前默认模型的试听使用所选音色，其他模型的试听用第一种音色。`vits-zh-ll` 有五种音色。

点击模型右侧的「导出」，统一保存为标准 `.tar.zst`；`.tar.bz2` 仅支持导入。导出的是当前模型库中的原始推理文件，不包含录音、聊天内容或默认音色设置；可用支持 Zstd 的 TAR 工具解包，也可直接重新导入。压缩在后台分块执行，实际体积和耗时取决于模型。模型所需文件总计最多 512 MiB，导入归档和展开的 TAR 最多 1 GiB。

删除只移除语音库中的副本，不修改原始压缩包。默认模型被删除后，该类型需要重新选择。缺文件的模型会标记为不可用，重新导入原包可修复。仅导入来自可信来源的模型。

## 聊天使用

- 设置默认识别模型后，聊天输入框出现麦克风图标。点击录音，再点停止，转写追加到当前草稿；可编辑后手动发送。软件使用默认麦克风，最长一段 90 秒，离开会话会取消录音或仍在运行的识别。
- 设置默认合成模型后，已结束的 AI 正文旁出现朗读按钮。点击播放，再点停止。播放使用 Windows 默认输出设备，不读取模型思考、工具过程、代码块或错误详情，也不会自动朗读。
- 录音、转写和播放故障会提示，不会阻断普通文字输入和发送。录音和生成音频不写入文件，也不随聊天导出。

## 验证

独立验证程序位于 `tool/speech_probe`。在该目录执行 `flutter pub get` 后运行：

```powershell
dart run bin/speech_probe.dart <DLL目录> <识别模型目录> <输入WAV> <合成模型目录> <输出WAV> '是不是频繁的'
```

DLL 目录为对应架构的 `sherpa_onnx_windows` 插件目录，例如 Pub 缓存中 `sherpa_onnx_windows-2.0.3/windows/x64`。使用识别包内 `test_wavs/2.wav` 可校验上面的预期词。验证程序写出 WAV 供人工试听，正式应用不落盘。应用子进程使用随应用打包的 ONNX Runtime，先从可执行文件所在目录加载，避免误用系统目录中的旧版本。

实机验收时完整停止旧的 `flutter run`，用 `flutter run -d windows` 重启。导入模型并试听后，在聊天点麦克风说一句中文，确认识别结果进入可编辑的草稿，手动发送后点击回复的朗读按钮，确认听到回复并验证停止按钮。

若录不到声音，先在「Windows 设置 → 系统 → 声音 → 输入」确认有默认麦克风，并确认说话时输入音量有变化，再检查「隐私和安全性 → 麦克风」是否允许桌面应用访问。若听不到声音，检查默认输出设备及应用音量。文件推理、原生播放完成事件和聊天控件测试均不替代这次实机验收。
