# AI 思考强度

当前模型支持思考强度时，点击主页模型入口先显示强度面板；点击面板顶部的模型名称进入模型列表。当前模型不支持强度时直接显示模型列表。选择支持强度的模型后进入对应面板，普通模型选中即关闭菜单。点击菜单外关闭。输入区显示当前模型及已保存的强度，不支持强度时只显示模型名称。

## 交互与滑条

强度面板使用 `lib/core/widgets/app_capsule_slider.dart` 的共享胶囊滑条。设备音量、亮度和振动保持原有连续滑条行为；强度滑条使用 `snapToDivisions`，固定等级点按模型能力生成。拖动时位置连续跟随鼠标，等级文字预览最近档位；松手后以 150ms 动画吸附到最近节点并保存，方向键每次移动一档。不在每个拖动事件中写入磁盘。白色圆形滑块半径从 7 动画放大到 10，松手恢复。保留键盘焦点和离散档位无障碍语义。强度面板与模型列表之间使用 150ms 渐变淡入淡出；系统减少动画时直接切换或定位。

不设置“默认”节点或恢复默认按钮，只显示模型实际支持的等级。初次使用或旧配置没有强度记录时，有“中”则选择中，否则优先高，再取第一个有效等级，并保存实际值。支持关闭思考的模型才有“关闭”档位。模型的可选等级通过 `AiReasoningCapabilities` 统一管理，UI、持久化校验及请求编码使用同一份定义。

## 能力范围

当前识别 OpenAI 的 o1、o3、o3-mini、o4-mini，以及代码中明确列出的 GPT-5 和 Codex 模型系列；DeepSeek 识别 `deepseek-flash` 和 `deepseek-v4-pro`。OpenAI 不同型号的可用等级不同；DeepSeek 提供关闭、低、高、最大。

标准模型发现接口不保证返回思考强度能力。当前采用明确模型 ID 的能力表，不对未知名称、第三方改名、旧版 `deepseek-chat`／`deepseek-reasoner` 或其他供应商猜测等级。新增型号或别名时须先核实供应商支持的参数和档位，再更新能力表及测试。第三方即使使用相同模型 ID，也可能没有实现对应参数，实际兼容性取决于服务端。

## 请求参数

| API | 强度参数编码 |
| --- | --- |
| OpenAI Chat Completions | 顶层 `reasoning_effort` |
| OpenAI Responses | `reasoning.effort` |
| DeepSeek Chat Completions | `thinking.type` 为 `enabled`，并设置 `reasoning_effort`；关闭时只设置 `thinking.type: disabled` |
| DeepSeek Responses | `reasoning.effort`，关闭时为 `none` |

未指定强度或当前模型不支持的等级不写入请求。等级选择按“服务 ID + 模型 ID”保存在现有 `ai.services.v2` 配置中；切换模型后分别恢复，删除服务或从服务移除模型时清除相应记录。写入失败恢复原先的选择，不覆盖密钥。旧配置没有此字段时补齐有效等级。

每轮发送时冻结服务、模型和强度配置。生成期间可修改下一轮的强度；本轮重试、工具调用后的后续请求继续使用本轮快照。展开消息的“用时”栏时，模型名称下方显示本轮实际使用的思考强度；不支持强度或没有记录的旧消息不显示该行。切换模型或强度不会回写旧消息。

## 参考来源

- [OpenAI reasoning 文档](https://developers.openai.com/api/docs/guides/reasoning/)：参数结构及各型号能力存在差异。
- [DeepSeek thinking mode 文档](https://api-docs.deepseek.com/guides/thinking_mode)：思考开关、有效强度和 Responses 映射。
- 用户提供的 Codex 仓库 `codex-rs/models-manager/models.json` 与 `codex-rs/protocol/src/openai_models.rs`：按模型声明可用档位，避免全局使用同一组强度选项。

回归验证覆盖两种协议参数、未指定参数省略、不支持等级过滤、按服务及模型隔离、保存恢复与失败回滚、生成中的配置快照，处理记录的强度快照，以及明暗主题和中英文窄窗口下的面板布局。
