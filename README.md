# 我们的家

三名玩家分别扮演三花、布偶、奶牛，由系统自动主持的故事棋盘游戏。

当前阶段：**M0 项目脚手架**。已提供本地角色选择、按选择顺序建立三只猫的开局状态，以及自动检查入口。还没有联网、棋盘移动、月份推进、战斗或剧情播放。

## 启动

使用 **Godot 4.6.1 stable**，GDScript、2D、Compatibility 渲染器，先面向 Windows。

在项目根目录打开 PowerShell：

```powershell
# 启动本地预览
powershell -ExecutionPolicy Bypass -File .\scripts\godot.ps1

# 打开 Godot 编辑器；也可从 Godot 项目管理器导入 project.godot
powershell -ExecutionPolicy Bypass -File .\scripts\godot.ps1 -GodotArgs '--editor'

# 自动检查：导入、行为检查、入口启动
powershell -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

首次运行若缺少 Godot 脚本类缓存，启动脚本会先执行无界面导入，再打开主场景。

脚本优先使用显式的 `-GodotPath`，其次是环境变量 `GODOT_BIN`，再查找项目上一级目录中的 `Godot_v4.6.1-stable_win64.exe`，最后查找 PATH 中的 `godot`。例如：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check.ps1 -GodotPath 'E:\MyGames\Godot_v4.6.1-stable_win64.exe'
```

本地预览中依次选择三只猫，再点击“建立本地预览”。界面应按选择顺序显示 1 级、野性 0/10、饱食度 3/5；“重新选择”可以清空重来。这些选择目前由同一台电脑完成。

## 从哪里看起

- [策划规则](docs/故事审阅与开工前条件.md)：用户确认的故事和规则，以及仍待确认的裁定。
- [技术方案与实施计划](docs/技术方案与实施计划.md)：先做什么、再做什么，以及各阶段验收条件。
- [协作与提交规范](CONTRIBUTING.md)：文档写作、代码检查和提交说明。
- [素材风格与生成规范](docs/素材风格与生成规范.md)：各专业的风格基准、素材来源与验收要求，当前画风仍待定。
- [项目指令](AGENTS.md)与[中文项目 skill](.agents/skills/our-home-workflow/SKILL.md)：约束后续代理在本项目内的工作。
- [Git 提交与推送 skill](.agents/skills/our-home-git/SKILL.md)：按任务范围组织提交，保留协作者改动并核对上传结果。

## 目录职责

| 路径 | 当前职责 |
|---|---|
| `src/app/` | 主场景与本地预览界面 |
| `src/domain/` | 开局规则、选择校验、独立的三猫初始状态 |
| `data/rules/` | 已确认规则的 Godot 资源 |
| `tests/` | 角色选择、状态隔离、非法输入、入口交互检查 |
| `scripts/` | Godot 定位、启动与统一检查 |
| `docs/` | 原故事截图、策划和技术文档 |

饱食度内部用半点整数保存：6 表示 3，10 表示 5，1 表示 0.5。界面只显示正常饱食度数值。经验表已配置，但升级和觉醒流程尚未实现。

Godot 生成的 `.gd.uid` 文件需要随源码提交；`.godot/` 缓存和 `.artifacts/` 检查日志被忽略。现有故事截图通过 `docs/.gdignore` 排除引擎导入，仍保留在文档目录中。

下一阶段按技术方案完成本地月份与行动的最小流程，然后尽早验证三人联机。
