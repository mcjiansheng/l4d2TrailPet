# Trail Pet

《求生之路 2》（Left 4 Dead 2）的跟随宠物模组，当前版本 **0.2.4**。

每名真人幸存者拥有一只跟随宠物，最多 8 只。宠物沿主人走过的路线移动，支持互动、召回、原地等待、跳舞和尝试指路。宠物没有实体碰撞，不参与战斗，也不造成伤害。

使用游戏自带的小矮人模型 `models/props_junk/gnome.mdl`，已有的小矮人替换模组会改变宠物外观。

## 安装

1. 下载仓库中的 [pet_companion.vpk](pet_companion.vpk)。
2. 将文件放入游戏目录的 `left4dead2\addons`。
3. 在单人战役或自己创建的本地服务器中加载地图，宠物会自动生成。服务器端也需要安装此包。

Windows 下也可以下载整个仓库，关闭游戏后在 PowerShell 中运行：

```powershell
.\Install.ps1
```

脚本会从 Steam 注册表读取默认游戏路径；其他安装位置可手动指定：

```powershell
.\Install.ps1 -GameDirectory 'D:\SteamLibrary\steamapps\common\Left 4 Dead 2'
```

安装脚本会保存并校验旧包，运行 `.\Restore.ps1` 可恢复该次安装前的版本。正常使用保持 `sv_cheats=0`。

## 使用

靠近并看着宠物，按 **E** 互动。按 **Y** 打开聊天后输入：

| 命令 | 功能 |
| --- | --- |
| `!pet help` | 查看命令 |
| `!pet status` | 查看当前状态 |
| `!pet come` | 召回到身前附近 |
| `!pet stay` | 原地等待 |
| `!pet follow` | 恢复跟随 |
| `!pet dance` | 开心扭动 |
| `!pet guide` | 尝试指路 |
| `!pet off` | 隐藏宠物 |
| `!pet on` | 重新启用 |

宠物卡住或掉队后会在附近恢复。指路使用地图导航数据；梯子、电梯和复杂机关仍待实测。

## 构建

源码位于 [pet_companion_src](pet_companion_src)，使用 L4D2 VScript（Squirrel）。修改 [config.nut](pet_companion_src/scripts/vscripts/trailpet/config.nut) 可调整模型、速度和跟随距离等参数，再用游戏自带的 `bin\vpk.exe` 重新构建：

```powershell
.\Build.ps1
# 手动指定游戏路径：
.\Build.ps1 -GameDirectory 'D:\SteamLibrary\steamapps\common\Left 4 Dead 2'
```

输出文件为 `pet_companion.vpk`。运行日志位于游戏目录的 `left4dead2\ems\trailpet_status.txt`。

## 0.2.4 状态

修复追到缓存目标后空等、台阶被当成墙、转角提前跳过、窄门预留过宽和跨楼层盲目直追。移动按实际引擎时间计算，并删去了重复的路径射线检测。

当前包已通过 `c1m1_hotel` 的楼梯、窄门和障碍检测诊断；玩家键鼠验收尚未完成。
