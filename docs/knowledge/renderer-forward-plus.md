# 渲染器切换（2026-10-01）

用户确认卡牌商店切换 Forward+。桌面采用 Forward+，Windows 明确使用 D3D12，移动端覆盖采用 Mobile。原配置备份在 outputs/renderer-forward-plus-20261001/project.godot.before；真实图形启动日志 startup.log 确认 RTX 4090 使用 D3D12 / Forward+，180 帧启动检查未记录报错。

本次仅切换渲染配置，不强制开启用户 HDR 开关。HDR 最终观感、全屏亮度及植物材质仍需实际体验验证；已运行的旧进程必须重启才会使用新渲染器。
