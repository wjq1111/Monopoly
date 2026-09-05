# 我们的家

三名玩家分别扮演三花、布偶、奶牛，由系统自动主持的故事棋盘游戏。

当前已接入 **Godot 棋盘界面首版与真实本地 ENet 服务器**：连接、选角、准备、进入棋盘、地块详情、Q 版棋子、仓库/角色面板往返和四格剧情接口预览。普通投骰行走、月份、物品结算、战斗、正式剧情触发及存档仍待实现。

## 先用一只猫试跑

使用 Godot **4.6.1 stable**。在项目目录打开 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\godot.ps1
```

点击“本机试跑 · 单猫”，选择一只猫，“我准备好了”→“进入棋盘”。按钮会自动启动本机独立无头服务器，只需要一个游戏窗口；离开或关窗口时会关闭自己创建的服务。

点棋盘格查看地点；“调试 · 移到这里”由服务器更新棋子位置。“看一段故事”打开四格接口预览，看完返回原棋盘。仓库和角色以弹层打开，保留局内状态。调试移动与剧情预览不会结算奖励、推进月份或代替正式骰子规则。

## 三名玩家连接

一台电脑启动服务器：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\server.ps1
```

三个客户端分别运行游戏，输入服务器电脑地址，点击“连接同伴的房间”，各选不同的猫并准备。默认端口为 UDP 27840；同一电脑地址为 127.0.0.1。服务器也是程序，不占第四名玩家席位。独立启动的服务器在关闭客户端后仍运行，启动器会显示它的 PID 和日志。

正式模式需要三人，不开放单猫调试移动。当前验证了同机真实 ENet 协议与独立服务；三台设备、外网连接、重连和完整游戏流程尚未验收。详细启动方式与接口见[本地服务器与联机接口](docs/本地服务器与联机接口.md)。

## 界面与素材

默认窗口 1600×900，基础布局和最小窗口 1280×720；16:9 与超宽布局保持比例，四组实测结果见[棋盘首版说明](docs/ui/Godot棋盘首版.md)。

三猫已有 Q 版候选头像。29 个原棋盘格位均已展示，01 烂尾楼、09 公园草丛、20 宠物医院、24 公园入口接入独立插画样张；其余 25 格为临时图形占位。剧情目前复用地点图作接口预览，正式四格分镜、整张背景、动画和声音继续制作。

## 开发与检查

```powershell
# 打开编辑器
powershell -ExecutionPolicy Bypass -File .\scripts\godot.ps1 -GodotArgs '--editor'

# 棋盘/本地联机需求完成后验收：功能+固定窗口稳定性
powershell -ExecutionPolicy Bypass -File .\scripts\board_check.ps1

# 只补测固定窗口稳定性；不重跑整个功能流程
powershell -ExecutionPolicy Bypass -File .\scripts\board_check.ps1 -StabilityOnly

# 明确需要主动轮转四组尺寸时
powershell -ExecutionPolicy Bypass -File .\scripts\board_check.ps1 -ResolutionSweep

# 原 M0 本地三猫脚手架完整回归，固定加载旧 main.tscn
powershell -ExecutionPolicy Bypass -File .\scripts\self_test.ps1 -RecordMovie
```

`board_check.ps1` 自动检查通过后退出 2，表示截图仍待实际审阅，记录位于 `.artifacts/board-interface/`；普通功能测试不再默认轮转分辨率，尺寸轮转须显式开启。它不代表完整游戏验收。开发中只做必要的针对性检查，一项需求完成后验收关联用例。用例、证据和未覆盖范围见[测试规范](docs/testing/测试流程与用例规范.md)及[执行记录](docs/testing/执行记录/)。

启动脚本优先取 `-GodotPath`，其次 `GODOT_BIN`、项目上级的 `Godot_v4.6.1-stable_win64.exe`，最后 PATH。首次缺少资源缓存时会先导入。Godot 的 `.gd.uid` 随源码保留；`.godot/` 和 `.artifacts/` 不提交。

## 文档和目录

- [工作与决策记录](docs/工作与决策记录.md)：每轮助手决定、做了什么、没做什么及原因。
- [策划规则](docs/故事审阅与开工前条件.md)、[技术计划](docs/技术方案与实施计划.md)、[需求矩阵](docs/testing/需求追踪矩阵.md)。
- [棋盘首版说明](docs/ui/Godot棋盘首版.md)、[原布局](docs/ui/界面布局与制作顺序.md)。
- [风格规范](docs/素材风格与生成规范.md)、[Q版头像记录](docs/art/Q版棋盘头像_v001.md)、[地块样张记录](docs/art/棋盘地块样张_v001.md)。
- [协作规范](CONTRIBUTING.md)、[中文工作技能](.agents/skills/our-home-workflow/SKILL.md)。

| 目录 | 职责 |
|---|---|
| src/app、src/ui | 入口、房间、常驻棋盘、复用面板与主题 |
| src/network | ENet 会话与服务器权威状态 |
| src/domain、data/rules | 领域规则、初始状态与已确认配置 |
| assets/art | 已接入的候选头像与地块样图 |
| tests、scripts | 需求关联的运行检查与启动入口 |
| docs | 原稿、策划、技术、素材、测试与逐轮记录 |

饱食度初始 3、上限 5，内部用半点整数 6/10 保存。当前猫等级 1、野性 0/10；不使用另一套“生命值”。
