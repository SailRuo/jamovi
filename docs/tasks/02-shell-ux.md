# P0 · 壳层交互

## 目标

- 左上汉堡改为「项目」文字按钮，打开原文件菜单（Backstage）
- 右上竖三点改为「设置」
- 右侧增加可贴边、可隐藏的「分析方法说明」
- 保持变量 / 数据 / 分析 / 编辑面板结构

## 现状

| 控件 | 实现 | 文件 |
|---|---|---|
| 汉堡文件按钮 | `mif-menu` 图标，无文字 | `client/main/ribbon.ts` `RibbonView` |
| 文件菜单内容 | New / Open / Special Import / Save / Save As / Export / Recents | `client/main/backstage.ts` `createOps()` |
| 竖三点 | `<jmv-appmenu>`，`mif-more-vert` | `client/main/ribbon/appmenu.ts` |
| 右侧说明栏 | 不存在；`jamovi.css` 有未使用的 `#help` | — |
| 分析选项 | 结果左侧 iframe | `client/main/optionspanel.ts` |

## 子任务

### 项目菜单

- [ ] **T-02-01** 汉堡图标改为可见文字「项目」（可保留快捷键）
- [ ] **T-02-02** Backstage 左侧标题 / logo 换成 X-Stat（随品牌任务）
- [ ] **T-02-03** 保持：新建、打开、保存、另存为、最近使用
- [ ] **T-02-04** 从项目菜单移除「特殊导入」和单一「导出」（改到 [03-file-io.md](./03-file-io.md)）

### 设置

- [ ] **T-02-05** AppMenu 触发器改为「设置」文字或齿轮 + 文字
- [ ] **T-02-06** 现有项保留：缩放、数字格式、绘图主题、语言、开发者模式
- [ ] **T-02-07** 增加：分析方法说明 显示/隐藏、默认批处理导出目录（可放到 P1）

### 分析方法说明

- [ ] **T-02-08** 新增右侧 Dock：默认可收起，贴窗口右缘；可固定展开
- [ ] **T-02-09** 内容随当前选中的分析变化（无分析时显示总览：标志物分析流程）
- [ ] **T-02-10** 文案来源：按分析 `ns` + `name` 映射到 Markdown/HTML（先做中文）
- [ ] **T-02-11** 第一批文案覆盖文档已写清的方法：描述、t/U/ANOVA、KM、Cox、相关、聚类
- [ ] **T-02-12** 说明栏不挡住结果导出和编辑注释

建议实现位置：

- 新组件 `client/main/methodhelp.ts` + CSS
- 由 `main.ts` / 分析选中事件注入当前 analysis id
- 文案目录例如 `client/assets/method-help/`

## 验收

- 点击「项目」打开原文件层；不再显示三横线作为唯一入口
- 点击「设置」打开原 AppMenu
- 打开任意分析后，右侧说明能切到对应方法；可隐藏后主区变宽

## 依赖

[01-branding.md](./01-branding.md) 的 logo。方法论文案可先用文档中的「方法 / 典型场景」段落。
