# X-Stat 开发任务

本目录是对照 `docs/X-Stat开发需求要点说明.docx` 与当前 jamovi 仓库拆出的开发计划。

**产品**：X-Stat  
**定位**：定量病理数据统计分析  
**底座**：本仓库 jamovi（Electron + TypeScript client + Python server + R engine）  
**外部系统**：X-Lab（项目管理，不在本仓库）

## 怎么用

1. 先读 [00-roadmap.md](./00-roadmap.md)：分期、依赖、需求对照。
2. 按阶段打开对应工作流文件，按勾选推进。
3. 需求文档里标了「？？？」或未拍板的项，集中在 [99-open-questions.md](./99-open-questions.md)。

## 工作流文件

| 文件 | 阶段 | 内容 | 主要改动范围 |
|---|---|---|---|
| [01-branding.md](./01-branding.md) | P0 | 去 jamovi 品牌，换成 X-Stat | 本仓库 client / electron / server / platform |
| [02-shell-ux.md](./02-shell-ux.md) | P0 | 项目菜单、设置、分析方法说明、标题栏 | 本仓库 client |
| [03-file-io.md](./03-file-io.md) | P0 | 数据替换、导出拆分 | 本仓库 client / server |
| [04-modules.md](./04-modules.md) | P0 | 预装插件、分析面板只显示指定模块 | 本仓库 + Docker + 外部 `.jmo` |
| [05-data-cleaning.md](./05-data-cleaning.md) | P1 | 缺失/异常/标准化/正态化工具，jReshape 挪到数据面板 | 本仓库 + 新模块 |
| [06-eda-plots.md](./06-eda-plots.md) | P1 | 绘图改 EDA、冲积图/和弦图、Box Plot 带 p 值 | 本仓库 + `plots` 子模块 |
| [07-batch.md](./07-batch.md) | P1 | 多指标批处理与结果批量导出 | 本仓库新能力 |
| [08-stats-workflows.md](./08-stats-workflows.md) | P2 | 比例分析、组间比较、相关、分类结局 | 新/改装模块 + 方法向导 |
| [09-survival-roc.md](./09-survival-roc.md) | P2 | 生存分析逐步流程、LASSO-Cox、ROC | ClinicoPath / jsurvival + Rj |
| [10-clustering.md](./10-clustering.md) | P2 | 聚类热图叠加临床变量 | snowCluster 增强 |
| [11-ai-archive.md](./11-ai-archive.md) | P3 | AI 解读、总结存档 | 新功能 |
| [12-xlab.md](./12-xlab.md) | P3 | 与 X-Lab 项目管理对接 | 协议 + X-Lab 侧 |
| [99-open-questions.md](./99-open-questions.md) | — | 文档未决项 | — |

## 仓库边界（先看清再开工）

本仓库**自带**的分析模块只有：

- `jmv`：探索 / t 检验 / ANOVA / 回归 / 频率等
- `plots`（scatr）：Bar / Box / Histogram / Scatter / Line

需求里点名、但**不在本仓库**的模块：

- ClinicoPath（含生存、冲积图、描述图）
- jReshape
- snowCluster
- jsurvival / Jsurvival
- Rj Editor

这些要以预装 `.jmo` 或独立模块仓库接入，不能只在 client 里“点出来”。

## 建议决策（计划已按此拆任务）

文档里有几处犹豫，计划采用如下默认方案，有异议再改 [99-open-questions.md](./99-open-questions.md)：

1. **批处理**：不新增独立 Ribbon Tab。EDA 和指定分析模块内放「批处理导出」按钮，底层共用一套 BatchRunner。
2. **分析方法说明**：右侧可贴边的可折叠说明栏，随当前分析切换内容。
3. **X-Lab**：本仓库只做文件约定与打开入口，卡片/工作流在 X-Lab。
4. **FDR 多重校正**：按文档「暂时不考虑」，放入 P3 以后。
5. **AGPL**：界面可换品牌，`LICENSE.md`、关于页和引用必须保留 jamovi 开源声明。
