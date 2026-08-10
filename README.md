# 秋招助手（macOS）

一个使用 SwiftUI 编写的原生 macOS 秋招求职记录工具。数据只保存在本机，不依赖账号或服务器。当前版本为 2.0。

## 已实现功能

- 公司、招聘项目和岗位投递记录
- 状态筛选、搜索和可拖拽流程看板
- 多轮面试、笔试、测评与 Offer 沟通记录
- 待办事项、截止时间和 macOS 本地通知
- 首页仪表盘、过久未更新提示和近期日程
- 投递趋势、回复率、面试率、Offer 率和渠道分析
- CSV 导入导出与完整 JSON 备份恢复
- 自动保存和状态变更历史
- 自定义流程状态和看板列
- 岗位多标签及筛选
- 简历版本管理与投递关联
- 月历视图
- 应用内智能提醒中心
- 技术面、产品面和 HR 面复盘模板
- 按岗位类别、城市和简历版本分析
- 第一版数据自动迁移
- 后台节能：窗口关闭后可按设置自动退出，窗口保留时使用 macOS App Nap

完整开发进度见 [`docs/TODO.md`](docs/TODO.md)。

## 构建

要求 macOS 14 或更高版本，以及 Xcode 16 或更高版本。

```bash
./Scripts/build_app.sh
```

构建结果位于 `dist/秋招助手.app`，可以直接双击运行，也可以复制到“应用程序”目录。

开发调试：

```bash
swift run --disable-sandbox
```

运行测试：

```bash
swift test --disable-sandbox
```

## 本地数据

首次启动会生成三条演示记录。正式数据默认存放在：

```text
~/Library/Application Support/AutumnJobs/job-data.json
```

可以在应用的“设置”页面导出 CSV 或创建完整 JSON 备份。
