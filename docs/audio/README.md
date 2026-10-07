> Local sync 2026-10-06: the original snapshot design and previews below are historical. The latest game uses 21 exact compatible narrative entries / 10 cues; 40 old entries are disabled and 58 latest entries remain unauthored. Use `local_narrative_compatibility.json` and `../knowledge/audio-local-sync.md` for current coverage. Generic audio and native film routing have passed local Godot verification.

# 音频接入与替换说明

这次按当前可执行文案配声。开头从雪线边缘的暴露强风，转入潮湿黑刺李林的遮蔽风声；追逐段不铺轻快旋律。脚步、远犬、水壶、围巾、石头和摘果动作在对应语句出现时触发。两次犬声使用同一声源，第二次更近、更清晰。普通说话、回忆、指路、选项悬停及每字打字都不额外制造动作声。`docs/audio/narrative_audio_plan.json` 保留原句、真实节点、分支、选择与设计理由；运行数据在 `assets/audio/narrative_cues.json`。

## 文件与范围

- `assets/audio/audio_catalog.json`：68 个稳定事件，音源、音量、路由、音高、循环、冷却、出处和状态均可编辑。
- `assets/audio/narrative_cues.json`：61 个正在使用的对白/分支节点，22 个有限动作音，另有「你停下」的停步命令。场间读档也恢复正确的环境，不会回退成鸟鸣与轻快音乐。
- `docs/audio/audio_inventory.csv`：可排序、可替换的完整事件表；原有影片音轨另列在目录的 existing_media 中。
- `assets/audio/licenses/`：CC0 来源、处理记录、作者和许可证证据。原有开场影片的版权来源没有重新认证，音轨未重制。
- `docs/audio/previews/`：76 秒叙事试听、40 秒卡牌/UI试听与时间线。这是按目录离线合成的试听，不是云端游戏录音。

当前素材是可替换占位。事件状态明确区分：56 个已接线事件、5 个备用事件、4 个通用后备场景、3 个未来章节接口。当前快照没有首章内容模块，不能把这些预留接口称为已发生的游戏内容。影片维持自己的配乐/音效，播放时游戏环境与音乐淡出。

## 播放路径

`AudioEvents` 是可选的薄入口，保证独立组件测试不依赖 Autoload。它只转发到唯一的 `GameAudio`。`NarrativeAudioDirector` 负责语句、暂停、跳字、切场与读档的节奏；不修改玩法、随机数、存档结构或故事。

Master 下为 Music、SFX。MusicMix 和 Cinematic 服从已有音乐滑杆；UI、Cards、World、Narrative、Ambience 服从已有音效滑杆。Narrative 的实例声像通过独立 Panner 子总线处理。短音最多 24 声，循环分层每层最多两个播放器交叉淡化；事件有冷却/复音限制。暂停时对白动作冻结，实际探索脚步停止；退回菜单或载入其他存档不会带入上一场景残留犬声。

## 替换一个音

1. 将有使用权的 OGG/WAV 放入 `assets/audio/`。循环素材应先检查接缝，不要只相信文件名写了 loop。
2. 在目录找到稳定事件 ID，改 `files` 路径；保留 ID。调整 `gain_db`、`pitch`、`loop`、`cooldown_ms`，登记 `source_url` 和 `license`。
3. 文案节奏改在 `narrative_cues.json`，使用当前真实 `text_key` 和精确短语。不要把一句「去溪里走」当成已经涉水。
4. Godot 4.7.1 打开项目等待导入。在游戏「设置 → 音频」测试总音量/音乐/音效的零值及恢复，试听后再细调。

## 验证与限制

自动验证包括音源加载、重复点击、冷却与复音、交叉淡化反转、暂停、音量零值、影片排他、对白短语、分支动作、取消探索、停步、切场与读档。完整结果见 `qa_report.json`。云端可运行完整 4.7.1 编辑器/游戏，画面使用软件 OpenGL；没有 ALSA 输出设备，Godot 回退到 Dummy。因此已验证实际事件路径和文件波形，但没有声称在云端扬声器上听过最终混音。请先听两段试听，再在有声音的设备检查真实游戏听感。

## 自动检查

Godot 4.7.1 在项目根目录运行：

- `--headless --path . --script tests/audio_service_suite.gd`
- `--headless --path . --script tests/narrative_audio_suite.gd`
- `--headless --path . --script tests/audio_gameplay_suite.gd -- --flow-qa`

加 `--audio-driver Dummy --rendering-method gl_compatibility` 可在无音频设备的 CI 运行。预览再生成可执行 `python tools/audio/render_audio_previews.py`（需要 NumPy 与 ffmpeg）。可带 `-- --audio-trace` 启动游戏，得到有因果顺序、节点、文件、音量和声像的事件日志；常规运行只保留 256 条环形记录，避免无限增长。
